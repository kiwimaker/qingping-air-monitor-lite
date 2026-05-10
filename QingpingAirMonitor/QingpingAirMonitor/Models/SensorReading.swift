import Foundation
import SwiftUI

/// Representa una lectura de sensores almacenada en el histórico
struct SensorReading: Identifiable, Sendable, Equatable {
    let id: Int64?
    let deviceMac: String
    let timestamp: Date
    let co2: Int?
    let pm25: Int?
    let pm10: Int?
    let temperature: Double?
    let humidity: Double?
    let battery: Int?

    /// Inicializador para crear una nueva lectura (sin ID, se asigna al insertar)
    init(
        deviceMac: String,
        timestamp: Date,
        co2: Int? = nil,
        pm25: Int? = nil,
        pm10: Int? = nil,
        temperature: Double? = nil,
        humidity: Double? = nil,
        battery: Int? = nil
    ) {
        self.id = nil
        self.deviceMac = deviceMac
        self.timestamp = timestamp
        self.co2 = co2
        self.pm25 = pm25
        self.pm10 = pm10
        self.temperature = temperature
        self.humidity = humidity
        self.battery = battery
    }

    /// Inicializador interno para lecturas desde la base de datos
    init(
        id: Int64,
        deviceMac: String,
        timestamp: Date,
        co2: Int?,
        pm25: Int?,
        pm10: Int?,
        temperature: Double?,
        humidity: Double?,
        battery: Int?
    ) {
        self.id = id
        self.deviceMac = deviceMac
        self.timestamp = timestamp
        self.co2 = co2
        self.pm25 = pm25
        self.pm10 = pm10
        self.temperature = temperature
        self.humidity = humidity
        self.battery = battery
    }

    /// Crear desde AirQualityData existente
    init(from data: AirQualityData, deviceMac: String) {
        self.id = nil
        self.deviceMac = deviceMac
        self.timestamp = data.timestamp ?? Date()
        self.co2 = data.co2
        self.pm25 = data.pm25
        self.pm10 = data.pm10
        self.temperature = data.temperature
        self.humidity = data.humidity
        self.battery = data.battery
    }

    /// Obtener valor para una métrica específica
    func value(for metric: SensorMetric) -> Double? {
        switch metric {
        case .co2: return co2.map { Double($0) }
        case .pm25: return pm25.map { Double($0) }
        case .pm10: return pm10.map { Double($0) }
        case .temperature: return temperature
        case .humidity: return humidity
        }
    }
}

// MARK: - Métricas de sensores

enum SensorMetric: String, CaseIterable, Identifiable {
    case co2
    case pm25
    case pm10
    case temperature
    case humidity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .co2: return "CO₂"
        case .pm25: return "PM2.5"
        case .pm10: return "PM10"
        case .temperature: return "Temperatura"
        case .humidity: return "Humedad"
        }
    }

    var unit: String {
        switch self {
        case .co2: return "ppm"
        case .pm25, .pm10: return "μg/m³"
        case .temperature: return "°C"
        case .humidity: return "%"
        }
    }

    var labelWithUnit: String {
        "\(label) (\(unit))"
    }

    var color: Color {
        switch self {
        case .co2: return .purple
        case .pm25: return .orange
        case .pm10: return .red
        case .temperature: return .yellow
        case .humidity: return .blue
        }
    }

    /// Umbrales para líneas de referencia en gráficas
    var thresholds: [(value: Double, label: String, color: Color)]? {
        switch self {
        case .co2:
            return [
                (800, "Bueno", .green),
                (1000, "Moderado", .yellow),
                (1500, "Malo", .red)
            ]
        case .pm25:
            return [
                (12, "Bueno", .green),
                (35, "Moderado", .yellow),
                (55, "Malo", .red)
            ]
        case .pm10:
            return [
                (54, "Bueno", .green),
                (154, "Moderado", .yellow),
                (254, "Malo", .red)
            ]
        case .temperature, .humidity:
            return nil
        }
    }
}

// MARK: - Rango temporal

enum TimeRange: String, CaseIterable, Identifiable {
    case day = "24h"
    case week = "7d"
    case month = "30d"
    case year = "1a"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "24 horas"
        case .week: return "7 días"
        case .month: return "30 días"
        case .year: return "1 año"
        }
    }

    var startDate: Date {
        let calendar = Calendar.current
        switch self {
        case .day: return calendar.date(byAdding: .day, value: -1, to: Date())!
        case .week: return calendar.date(byAdding: .day, value: -7, to: Date())!
        case .month: return calendar.date(byAdding: .month, value: -1, to: Date())!
        case .year: return calendar.date(byAdding: .year, value: -1, to: Date())!
        }
    }

    /// Tamaño de bucket (en segundos) para agregar lecturas al consultar el
    /// histórico. Mantiene la gráfica fluida en rangos largos sin perder forma.
    /// Aprox. puntos por rango:
    ///   - 24h crudo (~1 min): ~1440
    ///   - 7d / 10 min: ~1008
    ///   - 30d / 1 h: ~720
    ///   - 1a / 6 h: ~1460
    var aggregationBucketSeconds: Int {
        switch self {
        case .day: return 60          // sin agregación real
        case .week: return 10 * 60    // 10 min
        case .month: return 60 * 60   // 1 h
        case .year: return 6 * 3600   // 6 h
        }
    }
}

// MARK: - Estadísticas mensuales

struct MonthlyStats: Identifiable, Equatable {
    let id: String       // "2026-04"
    let year: Int
    let month: Int
    let count: Int

    let tempMin: Double?
    let tempAvg: Double?
    let tempMax: Double?

    let humMin: Double?
    let humAvg: Double?
    let humMax: Double?

    let co2Min: Int?
    let co2Avg: Int?
    let co2Max: Int?

    let pm25Avg: Int?
    let pm25Max: Int?

    let pm10Avg: Int?
    let pm10Max: Int?

    var monthLabel: String {
        let comps = DateComponents(year: year, month: month, day: 1)
        guard let date = Calendar.current.date(from: comps) else { return id }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).capitalized
    }

    var temperatureSummary: String { tripleSummary(min: tempMin, avg: tempAvg, max: tempMax, decimals: 1) }
    var humiditySummary: String { tripleSummary(min: humMin, avg: humAvg, max: humMax, decimals: 0) }
    var co2Summary: String { intDoubleSummary(min: co2Min, avg: co2Avg, max: co2Max) }
    var pm25Summary: String { pairSummary(avg: pm25Avg, max: pm25Max) }
    var pm10Summary: String { pairSummary(avg: pm10Avg, max: pm10Max) }

    private func tripleSummary(min: Double?, avg: Double?, max: Double?, decimals: Int) -> String {
        guard let min, let avg, let max else { return "—" }
        let fmt = "%.\(decimals)f"
        return "\(String(format: fmt, min)) · \(String(format: fmt, avg)) · \(String(format: fmt, max))"
    }

    private func intDoubleSummary(min: Int?, avg: Int?, max: Int?) -> String {
        guard let min, let avg, let max else { return "—" }
        return "\(min) · \(avg) · \(max)"
    }

    private func pairSummary(avg: Int?, max: Int?) -> String {
        guard let avg, let max else { return "—" }
        return "\(avg) · \(max)"
    }
}

// MARK: - Retención de histórico

enum HistoryRetention: String, CaseIterable, Identifiable {
    case unlimited = "unlimited"
    case oneYear = "1year"
    case sixMonths = "6months"
    case threeMonths = "3months"
    case oneMonth = "1month"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unlimited: return "Sin límite"
        case .oneYear: return "1 año"
        case .sixMonths: return "6 meses"
        case .threeMonths: return "3 meses"
        case .oneMonth: return "1 mes"
        }
    }

    /// Fecha límite para limpieza (nil = sin límite)
    var cutoffDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .unlimited: return nil
        case .oneYear: return calendar.date(byAdding: .year, value: -1, to: Date())
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: Date())
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: Date())
        case .oneMonth: return calendar.date(byAdding: .month, value: -1, to: Date())
        }
    }
}
