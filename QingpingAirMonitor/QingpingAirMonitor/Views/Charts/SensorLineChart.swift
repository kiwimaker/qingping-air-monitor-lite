import SwiftUI
import Charts

struct SensorLineChart: View {
    let readings: [SensorReading]
    let metric: SensorMetric
    let timeRange: TimeRange

    var body: some View {
        if readings.isEmpty {
            ContentUnavailableView(
                "Sin datos",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("No hay datos para el rango seleccionado")
            )
        } else {
            Chart {
                ForEach(readings) { reading in
                    if let value = reading.value(for: metric) {
                        LineMark(
                            x: .value("Tiempo", reading.timestamp),
                            y: .value(metric.label, value)
                        )
                        .foregroundStyle(metric.color.gradient)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Tiempo", reading.timestamp),
                            y: .value(metric.label, value)
                        )
                        .foregroundStyle(metric.color.opacity(0.1).gradient)
                    }
                }

                // Líneas de umbral de referencia
                if let thresholds = metric.thresholds {
                    ForEach(thresholds, id: \.value) { threshold in
                        RuleMark(y: .value("Nivel", threshold.value))
                            .foregroundStyle(threshold.color.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text(threshold.label)
                                    .font(.caption2)
                                    .foregroundColor(threshold.color)
                                    .padding(.horizontal, 4)
                                    .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
                                    .cornerRadius(2)
                            }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: dateFormat)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartYScale(domain: yAxisDomain)
        }
    }

    // MARK: - Computed Properties

    private var dateFormat: Date.FormatStyle {
        switch timeRange {
        case .day:
            return .dateTime.hour().minute()
        case .week:
            return .dateTime.weekday(.abbreviated).hour()
        case .month:
            return .dateTime.day().hour()
        case .year:
            return .dateTime.month(.abbreviated).day()
        }
    }

    private var yAxisDomain: ClosedRange<Double> {
        let values = readings.compactMap { $0.value(for: metric) }
        guard !values.isEmpty else { return 0...100 }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 100

        // Añadir padding al dominio
        let padding = (maxValue - minValue) * 0.1
        let lower = max(0, minValue - padding)
        let upper = maxValue + padding

        // Si hay umbrales, asegurar que estén visibles
        if let thresholds = metric.thresholds {
            let thresholdMax = thresholds.map(\.value).max() ?? 0
            return lower...max(upper, thresholdMax * 1.1)
        }

        return lower...upper
    }
}

// MARK: - Statistics View

struct ChartStatisticsView: View {
    let readings: [SensorReading]
    let metric: SensorMetric

    var body: some View {
        HStack(spacing: 20) {
            StatItem(label: "Mín", value: minValue, unit: metric.unit)
            Divider().frame(height: 30)
            StatItem(label: "Máx", value: maxValue, unit: metric.unit)
            Divider().frame(height: 30)
            StatItem(label: "Promedio", value: avgValue, unit: metric.unit)
            Divider().frame(height: 30)
            StatItem(label: "Registros", value: "\(readings.count)", unit: nil)
        }
    }

    private var values: [Double] {
        readings.compactMap { $0.value(for: metric) }
    }

    private var minValue: String {
        guard let min = values.min() else { return "—" }
        return formatValue(min)
    }

    private var maxValue: String {
        guard let max = values.max() else { return "—" }
        return formatValue(max)
    }

    private var avgValue: String {
        guard !values.isEmpty else { return "—" }
        let avg = values.reduce(0, +) / Double(values.count)
        return formatValue(avg)
    }

    private func formatValue(_ value: Double) -> String {
        switch metric {
        case .temperature, .humidity:
            return String(format: "%.1f", value)
        default:
            return String(format: "%.0f", value)
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.medium)
                    .monospacedDigit()
                if let unit = unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview {
    let sampleReadings = (0..<24).map { hour in
        SensorReading(
            deviceMac: "test",
            timestamp: Date().addingTimeInterval(TimeInterval(-hour * 3600)),
            co2: Int.random(in: 400...1200),
            pm25: Int.random(in: 5...50),
            temperature: Double.random(in: 18...26),
            humidity: Double.random(in: 40...70)
        )
    }

    return VStack {
        SensorLineChart(
            readings: sampleReadings,
            metric: .co2,
            timeRange: .day
        )
        .frame(height: 300)

        ChartStatisticsView(readings: sampleReadings, metric: .co2)
    }
    .padding()
}
