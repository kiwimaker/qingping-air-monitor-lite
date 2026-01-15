import Foundation

struct MenuBarDisplayOptions: Codable, Equatable {
    var showCO2: Bool = false
    var showPM25: Bool = false
    var showPM10: Bool = false
    var showTemperature: Bool = true
    var showHumidity: Bool = false

    static let `default` = MenuBarDisplayOptions()

    var hasAnyFieldEnabled: Bool {
        showCO2 || showPM25 || showPM10 || showTemperature || showHumidity
    }
}
