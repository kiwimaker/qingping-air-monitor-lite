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
