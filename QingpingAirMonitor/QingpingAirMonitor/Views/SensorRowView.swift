import SwiftUI

struct SensorRowView: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let level: AirQualityLevel

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(level.color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if level != .unknown {
                HStack(spacing: 4) {
                    Image(systemName: level.icon)
                        .font(.caption)
                    Text(level.rawValue)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(level.color.opacity(0.15))
                .foregroundColor(level.color)
                .cornerRadius(6)
            }
        }
    }
}

struct ClimateRowView: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack(spacing: 12) {
        SensorRowView(
            icon: "carbon.dioxide.cloud",
            title: "CO2",
            value: "850",
            unit: "ppm",
            level: .moderate
        )

        SensorRowView(
            icon: "smoke",
            title: "PM2.5",
            value: "12",
            unit: "µg/m³",
            level: .good
        )

        HStack(spacing: 20) {
            ClimateRowView(
                icon: "thermometer.medium",
                title: "Temperatura",
                value: "23.5",
                unit: "°C",
                color: .orange
            )

            ClimateRowView(
                icon: "humidity",
                title: "Humedad",
                value: "45",
                unit: "%",
                color: .blue
            )
        }
    }
    .padding()
    .frame(width: 280)
}
