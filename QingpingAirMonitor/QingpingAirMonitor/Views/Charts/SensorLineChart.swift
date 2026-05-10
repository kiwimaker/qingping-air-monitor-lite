import SwiftUI
import Charts

struct SensorLineChart: View {
    let readings: [SensorReading]
    let metric: SensorMetric
    let timeRange: TimeRange

    @State private var hoveredReading: SensorReading?

    var body: some View {
        if readings.isEmpty {
            ContentUnavailableView(
                "Sin datos",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("No hay datos para el rango seleccionado")
            )
        } else {
            Chart {
                // Zonas sin datos (gaps) en rojo
                ForEach(Array(gaps.enumerated()), id: \.offset) { _, gap in
                    RectangleMark(
                        xStart: .value("Inicio", gap.start),
                        xEnd: .value("Fin", gap.end)
                    )
                    .foregroundStyle(Color.red.opacity(0.15))
                }

                // Línea + área, segmentadas para no interpolar sobre huecos
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    ForEach(segment) { reading in
                        if let value = reading.value(for: metric) {
                            LineMark(
                                x: .value("Tiempo", reading.timestamp),
                                y: .value(metric.label, value),
                                series: .value("seg", index)
                            )
                            .foregroundStyle(metric.color.gradient)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Tiempo", reading.timestamp),
                                y: .value(metric.label, value),
                                series: .value("seg", index)
                            )
                            .foregroundStyle(metric.color.opacity(0.1).gradient)
                            .interpolationMethod(.catmullRom)
                        }
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

                // Indicador de hover
                if let hovered = hoveredReading,
                   let value = hovered.value(for: metric) {
                    RuleMark(x: .value("Hover", hovered.timestamp))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                    PointMark(
                        x: .value("Tiempo", hovered.timestamp),
                        y: .value(metric.label, value)
                    )
                    .foregroundStyle(metric.color)
                    .symbolSize(90)
                    .annotation(
                        position: .top,
                        spacing: 8,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        tooltip(for: hovered, value: value)
                    }
                }
            }
            .chartXAxis { xAxisContent }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartYScale(domain: yAxisDomain)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                guard let anchor = proxy.plotFrame else {
                                    hoveredReading = nil
                                    return
                                }
                                let frame = geo[anchor]
                                let xInPlot = loc.x - frame.origin.x
                                guard xInPlot >= 0, xInPlot <= frame.width else {
                                    hoveredReading = nil
                                    return
                                }
                                if let date: Date = proxy.value(atX: xInPlot) {
                                    hoveredReading = nearestReading(to: date)
                                }
                            case .ended:
                                hoveredReading = nil
                            }
                        }
                }
            }
        }
    }

    // MARK: - Tooltip

    @ViewBuilder
    private func tooltip(for reading: SensorReading, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(reading.timestamp, format: tooltipDateFormat)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(formatValue(value))
                    .font(.callout)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(metric.color)
                Text(metric.unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.15), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary.opacity(0.25))
        )
    }

    private func formatValue(_ value: Double) -> String {
        switch metric {
        case .temperature, .humidity: return String(format: "%.1f", value)
        default: return String(format: "%.0f", value)
        }
    }

    private func nearestReading(to date: Date) -> SensorReading? {
        readings.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) <
            abs($1.timestamp.timeIntervalSince(date))
        })
    }

    // MARK: - Eje X por rango

    @AxisContentBuilder
    private var xAxisContent: some AxisContent {
        switch timeRange {
        case .day:
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour())
            }
        case .week:
            AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated).day())
            }
        case .month:
            AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        case .year:
            AxisMarks(values: .stride(by: .month, count: 1)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
    }

    private var tooltipDateFormat: Date.FormatStyle {
        switch timeRange {
        case .day: return .dateTime.hour().minute()
        case .week: return .dateTime.weekday(.abbreviated).hour().minute()
        case .month: return .dateTime.day().month(.abbreviated).hour().minute()
        case .year: return .dateTime.day().month(.abbreviated).year()
        }
    }

    // MARK: - Detección de gaps (zonas sin datos)

    /// Umbral a partir del cual un salto entre lecturas se considera "sin datos".
    /// Los dispositivos Qingping suelen reportar cada 5-15 min; aplicamos un umbral
    /// generoso para no marcar como hueco la cadencia normal.
    private var gapThreshold: TimeInterval {
        switch timeRange {
        case .day: return 30 * 60          // 30 min
        case .week: return 2 * 3600        // 2 h
        case .month: return 6 * 3600       // 6 h
        case .year: return 24 * 3600       // 1 día
        }
    }

    private var sortedReadings: [SensorReading] {
        readings.sorted { $0.timestamp < $1.timestamp }
    }

    private var gaps: [(start: Date, end: Date)] {
        let sorted = sortedReadings
        guard sorted.count > 1 else { return [] }
        var out: [(Date, Date)] = []
        let threshold = gapThreshold
        for i in 1..<sorted.count {
            let delta = sorted[i].timestamp.timeIntervalSince(sorted[i - 1].timestamp)
            if delta > threshold {
                out.append((sorted[i - 1].timestamp, sorted[i].timestamp))
            }
        }
        return out
    }

    /// Particiona las lecturas en segmentos contiguos para que la línea no interpole
    /// sobre los huecos.
    private var segments: [[SensorReading]] {
        let sorted = sortedReadings
        guard !sorted.isEmpty else { return [] }
        var segs: [[SensorReading]] = []
        var current: [SensorReading] = [sorted[0]]
        let threshold = gapThreshold
        for i in 1..<sorted.count {
            let delta = sorted[i].timestamp.timeIntervalSince(sorted[i - 1].timestamp)
            if delta > threshold {
                segs.append(current)
                current = [sorted[i]]
            } else {
                current.append(sorted[i])
            }
        }
        segs.append(current)
        return segs
    }

    // MARK: - Eje Y

    private var yAxisDomain: ClosedRange<Double> {
        let values = readings.compactMap { $0.value(for: metric) }
        guard !values.isEmpty else { return 0...100 }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 100

        let padding = (maxValue - minValue) * 0.1
        let lower = max(0, minValue - padding)
        let upper = maxValue + padding

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
