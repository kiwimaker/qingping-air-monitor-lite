import SwiftUI

struct AirQualityData {
    let co2: Int?
    let pm25: Int?
    let pm10: Int?
    let temperature: Double?
    let humidity: Double?
    let battery: Int?
    let timestamp: Date?

    var co2Level: AirQualityLevel {
        guard let co2 = co2 else { return .unknown }
        switch co2 {
        case 0..<800: return .good
        case 800..<1000: return .moderate
        case 1000..<1500: return .poor
        default: return .veryPoor
        }
    }

    var pm25Level: AirQualityLevel {
        guard let pm25 = pm25 else { return .unknown }
        switch pm25 {
        case 0..<12: return .good
        case 12..<35: return .moderate
        case 35..<55: return .poor
        default: return .veryPoor
        }
    }

    var pm10Level: AirQualityLevel {
        guard let pm10 = pm10 else { return .unknown }
        switch pm10 {
        case 0..<54: return .good
        case 54..<154: return .moderate
        case 154..<254: return .poor
        default: return .veryPoor
        }
    }
}

enum AirQualityLevel: String {
    case good = "Bueno"
    case moderate = "Moderado"
    case poor = "Malo"
    case veryPoor = "Muy Malo"
    case unknown = "—"

    var color: Color {
        switch self {
        case .good: return .green
        case .moderate: return .yellow
        case .poor: return .orange
        case .veryPoor: return .red
        case .unknown: return .gray
        }
    }

    var icon: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.circle.fill"
        case .poor: return "exclamationmark.triangle.fill"
        case .veryPoor: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}
