import Foundation

struct DevicesResponse: Codable {
    let devices: [Device]
}

struct Device: Codable, Identifiable {
    let mac: String
    let name: String?
    let product: ProductInfo?
    let info: DeviceInfo?

    var id: String { mac }

    struct ProductInfo: Codable {
        let name: String?
        let model: String?
    }

    struct DeviceInfo: Codable {
        let status: Int?
    }
}

struct DeviceDataResponse: Codable {
    let total: Int
    let devices: [DeviceWithData]
}

struct DeviceWithData: Codable, Identifiable {
    let info: DeviceBasicInfo
    let data: SensorData?

    var id: String { info.mac }

    struct DeviceBasicInfo: Codable {
        let mac: String
        let name: String?
        let version: String?
    }

    struct SensorData: Codable {
        let timestamp: TimestampValue?
        let battery: SensorValue?
        let temperature: SensorValue?
        let humidity: SensorValue?
        let co2: SensorValue?
        let pm25: SensorValue?
        let pm10: SensorValue?
        let tvoc: SensorValue?

        struct TimestampValue: Codable {
            let value: Int
        }

        struct SensorValue: Codable {
            let value: Double
        }
    }
}

// MARK: - Historical Data Response (formato diferente de la API)

struct HistoricalDataResponse: Codable {
    let total: Int
    let data: [HistoricalReading]
}

struct HistoricalReading: Codable {
    let timestamp: TimestampValue
    let battery: SensorValue?
    let temperature: SensorValue?
    let humidity: SensorValue?
    let co2: SensorValue?
    let pm25: SensorValue?
    let pm10: SensorValue?
    let tvoc: SensorValue?

    struct TimestampValue: Codable {
        let value: Int
    }

    struct SensorValue: Codable {
        let value: Double
    }
}
