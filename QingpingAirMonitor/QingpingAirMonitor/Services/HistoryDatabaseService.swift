import Foundation
import SQLite3

/// Actor para manejo de base de datos SQLite de histórico de lecturas
actor HistoryDatabaseService {
    private var db: OpaquePointer?
    private let dbPath: URL

    // MARK: - Initialization

    init() throws {
        // ~/Library/Application Support/QingpingAirMonitor/history.sqlite
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("QingpingAirMonitor", isDirectory: true)

        try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        dbPath = appFolder.appendingPathComponent("history.sqlite")
        try openDatabase()
        try createTables()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() throws {
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw DatabaseError.cannotOpen(path: dbPath.path)
        }

        // Optimizaciones de performance
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL", nil, nil, nil)
    }

    private func createTables() throws {
        // Crear tabla e índices básicos
        let sql = """
            CREATE TABLE IF NOT EXISTS sensor_readings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                device_mac TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                co2 INTEGER,
                pm25 INTEGER,
                pm10 INTEGER,
                temperature REAL,
                humidity REAL,
                battery INTEGER,
                created_at INTEGER DEFAULT (strftime('%s', 'now'))
            );
            CREATE INDEX IF NOT EXISTS idx_readings_device_timestamp
                ON sensor_readings(device_mac, timestamp DESC);
            CREATE INDEX IF NOT EXISTS idx_readings_timestamp
                ON sensor_readings(timestamp);
        """

        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.tableCreationFailed
        }

        // Intentar crear índice único (puede fallar si hay duplicados existentes)
        // Primero eliminar duplicados si existen
        let cleanupSQL = """
            DELETE FROM sensor_readings
            WHERE id NOT IN (
                SELECT MIN(id)
                FROM sensor_readings
                GROUP BY device_mac, timestamp
            );
        """
        sqlite3_exec(db, cleanupSQL, nil, nil, nil)

        // Ahora crear el índice único
        let uniqueIndexSQL = """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_device_timestamp
                ON sensor_readings(device_mac, timestamp);
        """
        sqlite3_exec(db, uniqueIndexSQL, nil, nil, nil)
    }

    // MARK: - Insert

    func insertReading(_ reading: SensorReading) throws {
        let sql = """
            INSERT OR IGNORE INTO sensor_readings
            (device_mac, timestamp, co2, pm25, pm10, temperature, humidity, battery)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        sqlite3_bind_text(stmt, 1, reading.deviceMac, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, Int64(reading.timestamp.timeIntervalSince1970))
        bindOptionalInt(stmt, 3, reading.co2)
        bindOptionalInt(stmt, 4, reading.pm25)
        bindOptionalInt(stmt, 5, reading.pm10)
        bindOptionalDouble(stmt, 6, reading.temperature)
        bindOptionalDouble(stmt, 7, reading.humidity)
        bindOptionalInt(stmt, 8, reading.battery)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.insertFailed
        }
    }

    // MARK: - Query

    func fetchReadings(deviceMac: String, from startDate: Date, to endDate: Date) throws -> [SensorReading] {
        let sql = """
            SELECT id, device_mac, timestamp, co2, pm25, pm10, temperature, humidity, battery
            FROM sensor_readings
            WHERE device_mac = ? AND timestamp BETWEEN ? AND ?
            ORDER BY timestamp ASC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        sqlite3_bind_text(stmt, 1, deviceMac, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, Int64(startDate.timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 3, Int64(endDate.timeIntervalSince1970))

        var readings: [SensorReading] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let reading = SensorReading(
                id: sqlite3_column_int64(stmt, 0),
                deviceMac: String(cString: sqlite3_column_text(stmt, 1)),
                timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2))),
                co2: columnOptionalInt(stmt, 3),
                pm25: columnOptionalInt(stmt, 4),
                pm10: columnOptionalInt(stmt, 5),
                temperature: columnOptionalDouble(stmt, 6),
                humidity: columnOptionalDouble(stmt, 7),
                battery: columnOptionalInt(stmt, 8)
            )
            readings.append(reading)
        }
        return readings
    }

    /// Fetch agregado: agrupa lecturas en buckets de `bucketSeconds` y promedia
    /// los valores. Reduce drásticamente el número de puntos para rangos largos.
    /// Si `bucketSeconds <= 60`, hace fallback a `fetchReadings`.
    func fetchAggregatedReadings(
        deviceMac: String,
        from startDate: Date,
        to endDate: Date,
        bucketSeconds: Int
    ) throws -> [SensorReading] {
        guard bucketSeconds > 60 else {
            return try fetchReadings(deviceMac: deviceMac, from: startDate, to: endDate)
        }

        let sql = """
            SELECT
                (timestamp / ?) * ? AS bucket,
                AVG(co2) AS co2,
                AVG(pm25) AS pm25,
                AVG(pm10) AS pm10,
                AVG(temperature) AS temperature,
                AVG(humidity) AS humidity,
                AVG(battery) AS battery
            FROM sensor_readings
            WHERE device_mac = ? AND timestamp BETWEEN ? AND ?
            GROUP BY bucket
            ORDER BY bucket ASC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        sqlite3_bind_int64(stmt, 1, Int64(bucketSeconds))
        sqlite3_bind_int64(stmt, 2, Int64(bucketSeconds))
        sqlite3_bind_text(stmt, 3, deviceMac, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 4, Int64(startDate.timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 5, Int64(endDate.timeIntervalSince1970))

        let halfBucket = Int64(bucketSeconds) / 2
        var readings: [SensorReading] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let bucketStart = sqlite3_column_int64(stmt, 0)
            // Centrar timestamp en mitad del bucket → líneas alineadas con la ventana real
            let centerTs = TimeInterval(bucketStart + halfBucket)

            let co2 = columnOptionalDouble(stmt, 1).map { Int($0.rounded()) }
            let pm25 = columnOptionalDouble(stmt, 2).map { Int($0.rounded()) }
            let pm10 = columnOptionalDouble(stmt, 3).map { Int($0.rounded()) }
            let temperature = columnOptionalDouble(stmt, 4)
            let humidity = columnOptionalDouble(stmt, 5)
            let battery = columnOptionalDouble(stmt, 6).map { Int($0.rounded()) }

            // id = bucketStart para identidad estable (suficiente para Identifiable)
            let reading = SensorReading(
                id: bucketStart,
                deviceMac: deviceMac,
                timestamp: Date(timeIntervalSince1970: centerTs),
                co2: co2,
                pm25: pm25,
                pm10: pm10,
                temperature: temperature,
                humidity: humidity,
                battery: battery
            )
            readings.append(reading)
        }
        return readings
    }

    func fetchAllReadings(deviceMac: String) throws -> [SensorReading] {
        let sql = """
            SELECT id, device_mac, timestamp, co2, pm25, pm10, temperature, humidity, battery
            FROM sensor_readings
            WHERE device_mac = ?
            ORDER BY timestamp ASC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, deviceMac, -1, SQLITE_TRANSIENT)

        var readings: [SensorReading] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let reading = SensorReading(
                id: sqlite3_column_int64(stmt, 0),
                deviceMac: String(cString: sqlite3_column_text(stmt, 1)),
                timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2))),
                co2: columnOptionalInt(stmt, 3),
                pm25: columnOptionalInt(stmt, 4),
                pm10: columnOptionalInt(stmt, 5),
                temperature: columnOptionalDouble(stmt, 6),
                humidity: columnOptionalDouble(stmt, 7),
                battery: columnOptionalInt(stmt, 8)
            )
            readings.append(reading)
        }
        return readings
    }

    // MARK: - Statistics

    func getRecordCount(deviceMac: String? = nil) -> Int {
        let sql: String
        if deviceMac != nil {
            sql = "SELECT COUNT(*) FROM sensor_readings WHERE device_mac = ?"
        } else {
            sql = "SELECT COUNT(*) FROM sensor_readings"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }

        if let mac = deviceMac {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, mac, -1, SQLITE_TRANSIENT)
        }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    func getDateRange(deviceMac: String? = nil) -> (oldest: Date?, newest: Date?) {
        let sql: String
        if deviceMac != nil {
            sql = "SELECT MIN(timestamp), MAX(timestamp) FROM sensor_readings WHERE device_mac = ?"
        } else {
            sql = "SELECT MIN(timestamp), MAX(timestamp) FROM sensor_readings"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return (nil, nil)
        }
        defer { sqlite3_finalize(stmt) }

        if let mac = deviceMac {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, mac, -1, SQLITE_TRANSIENT)
        }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let oldest = sqlite3_column_type(stmt, 0) != SQLITE_NULL
                ? Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 0)))
                : nil
            let newest = sqlite3_column_type(stmt, 1) != SQLITE_NULL
                ? Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 1)))
                : nil
            return (oldest, newest)
        }
        return (nil, nil)
    }

    func getDatabaseSize() -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: dbPath.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    /// Obtiene el timestamp del último registro para un dispositivo
    func getLastTimestamp(deviceMac: String) -> Date? {
        let sql = "SELECT MAX(timestamp) FROM sensor_readings WHERE device_mac = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, deviceMac, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) != SQLITE_NULL {
            let timestamp = sqlite3_column_int64(stmt, 0)
            return Date(timeIntervalSince1970: TimeInterval(timestamp))
        }
        return nil
    }

    /// Inserta múltiples lecturas de forma eficiente (en una transacción)
    func insertReadings(_ readings: [SensorReading]) throws {
        guard !readings.isEmpty else { return }

        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)

        do {
            for reading in readings {
                try insertReading(reading)
            }
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    /// Inserta múltiples lecturas ignorando duplicados (basado en device_mac + timestamp)
    func insertReadingsIgnoringDuplicates(_ readings: [SensorReading]) throws {
        guard !readings.isEmpty else { return }

        let sql = """
            INSERT OR IGNORE INTO sensor_readings
            (device_mac, timestamp, co2, pm25, pm10, temperature, humidity, battery)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """

        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var insertedCount = 0

        for reading in readings {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)

            sqlite3_bind_text(stmt, 1, reading.deviceMac, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, Int64(reading.timestamp.timeIntervalSince1970))
            bindOptionalInt(stmt, 3, reading.co2)
            bindOptionalInt(stmt, 4, reading.pm25)
            bindOptionalInt(stmt, 5, reading.pm10)
            bindOptionalDouble(stmt, 6, reading.temperature)
            bindOptionalDouble(stmt, 7, reading.humidity)
            bindOptionalInt(stmt, 8, reading.battery)

            if sqlite3_step(stmt) == SQLITE_DONE {
                if sqlite3_changes(db) > 0 {
                    insertedCount += 1
                }
            }
        }

        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    // MARK: - Cleanup

    func deleteOldReadings(olderThan date: Date) throws -> Int {
        let sql = "DELETE FROM sensor_readings WHERE timestamp < ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(date.timeIntervalSince1970))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.deleteFailed
        }

        return Int(sqlite3_changes(db))
    }

    func deleteAllReadings() throws {
        let sql = "DELETE FROM sensor_readings"

        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.deleteFailed
        }

        // Vacuum para recuperar espacio
        sqlite3_exec(db, "VACUUM", nil, nil, nil)
    }

    // MARK: - Export

    func exportToCSV(deviceMac: String, from startDate: Date, to endDate: Date) throws -> String {
        let readings = try fetchReadings(deviceMac: deviceMac, from: startDate, to: endDate)
        return generateCSV(from: readings)
    }

    func exportAllToCSV(deviceMac: String) throws -> String {
        let readings = try fetchAllReadings(deviceMac: deviceMac)
        return generateCSV(from: readings)
    }

    private func generateCSV(from readings: [SensorReading]) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        var csv = "timestamp,co2,pm25,pm10,temperature,humidity,battery\n"

        for reading in readings {
            let timestamp = dateFormatter.string(from: reading.timestamp)
            let co2Str = reading.co2.map { String($0) } ?? ""
            let pm25Str = reading.pm25.map { String($0) } ?? ""
            let pm10Str = reading.pm10.map { String($0) } ?? ""
            let tempStr = reading.temperature.map { String(format: "%.1f", $0) } ?? ""
            let humStr = reading.humidity.map { String(format: "%.1f", $0) } ?? ""
            let battStr = reading.battery.map { String($0) } ?? ""

            let row = "\(timestamp),\(co2Str),\(pm25Str),\(pm10Str),\(tempStr),\(humStr),\(battStr)"
            csv += row + "\n"
        }

        return csv
    }

    // MARK: - Binding Helpers

    private func bindOptionalInt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value = value {
            sqlite3_bind_int(stmt, index, Int32(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value = value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnOptionalInt(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return Int(sqlite3_column_int(stmt, index))
    }

    private func columnOptionalDouble(_ stmt: OpaquePointer?, _ index: Int32) -> Double? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return sqlite3_column_double(stmt, index)
    }
}

// MARK: - Errors

enum DatabaseError: LocalizedError {
    case cannotOpen(path: String)
    case tableCreationFailed
    case prepareFailed
    case insertFailed
    case deleteFailed
    case queryFailed

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let path): return "No se pudo abrir la base de datos en: \(path)"
        case .tableCreationFailed: return "Error al crear las tablas"
        case .prepareFailed: return "Error al preparar la consulta"
        case .insertFailed: return "Error al guardar la lectura"
        case .deleteFailed: return "Error al eliminar datos"
        case .queryFailed: return "Error en la consulta"
        }
    }
}
