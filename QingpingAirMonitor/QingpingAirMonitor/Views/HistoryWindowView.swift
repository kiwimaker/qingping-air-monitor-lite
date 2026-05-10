import SwiftUI
import Charts
import UniformTypeIdentifiers

enum HistoryViewMode: String, CaseIterable, Identifiable {
    case chart, stats
    var id: String { rawValue }
    var label: String {
        switch self {
        case .chart: return "Gráfica"
        case .stats: return "Estadísticas"
        }
    }
}

struct HistoryWindowView: View {
    @EnvironmentObject var appState: AppState

    @State private var viewMode: HistoryViewMode = .chart
    @State private var selectedMetric: SensorMetric = .co2
    @State private var selectedRange: TimeRange = .day
    @State private var readings: [SensorReading] = []
    @State private var monthlyStats: [MonthlyStats] = []
    @State private var isLoading = false
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
                .padding()
                .background(Color(NSColor.windowBackgroundColor))

            // Banner de progreso o resultado de la sincronización
            if appState.isSyncingHistory || appState.syncProgress != nil {
                syncBanner
            } else if let error = appState.lastSyncError {
                syncErrorBanner(error)
            } else if let summary = appState.lastSyncSummary {
                syncSummaryBanner(summary)
            }

            Divider()

            // Content
            if !appState.isHistoryEnabled {
                historyDisabledView
            } else if isLoading {
                loadingView
            } else {
                switch viewMode {
                case .chart:
                    if readings.isEmpty { emptyView } else { chartContent }
                case .stats:
                    if monthlyStats.isEmpty { emptyStatsView } else { statsContent }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .onAppear { loadData() }
        .onChange(of: viewMode) { loadData() }
        .onChange(of: selectedRange) { loadData() }
        .onChange(of: appState.selectedDeviceMac) { loadData() }
        .onChange(of: appState.isSyncingHistory) { _, syncing in
            if !syncing { loadData() }
        }
    }

    private var syncBanner: some View {
        let progress = appState.syncProgress
        return HStack(spacing: 10) {
            if let fraction = progress?.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 220)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 220)
            }

            Text(syncStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }

    private var syncStatusText: String {
        guard let progress = appState.syncProgress else {
            return "Sincronizando…"
        }
        switch progress.phase {
        case .connecting:
            return "Conectando con la nube…"
        case .fetching:
            if progress.total > 0 {
                return "Descargando \(progress.loaded) / \(progress.total) lecturas…"
            }
            return "Descargando lecturas…"
        case .saving:
            return "Guardando \(progress.total) lecturas en el histórico…"
        case .scanningGaps:
            return "Analizando huecos en el histórico…"
        case .fillingGap(let index, let count):
            if progress.total > 0 {
                return "Hueco \(index)/\(count) · \(progress.loaded)/\(progress.total) lecturas"
            }
            return "Rellenando hueco \(index) de \(count)…"
        }
    }

    private func syncErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Sincronización fallida: \(message)")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Cerrar") { appState.lastSyncError = nil }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    private func syncSummaryBanner(_ summary: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(summary)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Ocultar") { appState.lastSyncSummary = nil }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.08))
    }

    // MARK: - Subviews

    private var toolbar: some View {
        HStack {
            // Modo de vista (gráfica vs estadísticas)
            Picker("Vista", selection: $viewMode) {
                ForEach(HistoryViewMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)

            if viewMode == .chart {
                Divider().frame(height: 18)

                // Selector de métrica
                Picker("Métrica", selection: $selectedMetric) {
                    ForEach(SensorMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
            }

            Spacer()

            if viewMode == .chart {
                // Selector de rango temporal
                Picker("Rango", selection: $selectedRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }

            // Menú de sincronización desde la nube
            Menu {
                Button("Sincronizar últimos 30 días") {
                    Task {
                        await appState.forceSyncHistory(days: 30)
                        loadData()
                    }
                }
                Button("Rellenar huecos del histórico") {
                    Task {
                        await appState.syncHistoryGaps()
                        loadData()
                    }
                }
            } label: {
                if appState.isSyncingHistory {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sincronización con la nube")
            .disabled(appState.isSyncingHistory)

            // Botón exportar
            Button {
                exportCurrentView()
            } label: {
                if isExporting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .buttonStyle(.borderless)
            .help("Exportar datos visibles a CSV")
            .disabled(viewMode != .chart || readings.isEmpty || isExporting)
        }
    }

    private var historyDisabledView: some View {
        ContentUnavailableView {
            Label("Histórico deshabilitado", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Activa el histórico en Ajustes > Histórico para comenzar a guardar datos.")
        } actions: {
            Button("Abrir Ajustes") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
            Text("Cargando datos...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "Sin datos",
            systemImage: "chart.line.uptrend.xyaxis",
            description: Text("No hay datos registrados para \(selectedRange.label)")
        )
    }

    private var emptyStatsView: some View {
        ContentUnavailableView(
            "Sin estadísticas",
            systemImage: "tablecells",
            description: Text("Aún no hay suficientes lecturas almacenadas para calcular estadísticas mensuales.")
        )
    }

    private var statsContent: some View {
        VStack(spacing: 0) {
            // Cabecera con leyenda
            HStack {
                Text("Resumen mensual · valores: mín · media · máx (PM: media · máx)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(monthlyStats.count) meses")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Table(monthlyStats) {
                TableColumn("Mes") { stat in
                    Text(stat.monthLabel).fontWeight(.medium)
                }
                .width(min: 130, ideal: 150)

                TableColumn("Lecturas") { stat in
                    Text("\(stat.count)").monospacedDigit()
                }
                .width(min: 70, ideal: 80)

                TableColumn("Temp (°C)") { stat in
                    Text(stat.temperatureSummary).monospacedDigit()
                }
                .width(min: 130, ideal: 150)

                TableColumn("Hum (%)") { stat in
                    Text(stat.humiditySummary).monospacedDigit()
                }
                .width(min: 110, ideal: 130)

                TableColumn("CO₂ (ppm)") { stat in
                    Text(stat.co2Summary).monospacedDigit()
                }
                .width(min: 130, ideal: 150)

                TableColumn("PM2.5 (μg/m³)") { stat in
                    Text(stat.pm25Summary).monospacedDigit()
                }
                .width(min: 100, ideal: 110)

                TableColumn("PM10 (μg/m³)") { stat in
                    Text(stat.pm10Summary).monospacedDigit()
                }
                .width(min: 100, ideal: 110)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var chartContent: some View {
        VStack(spacing: 0) {
            // Gráfica
            SensorLineChart(
                readings: readings,
                metric: selectedMetric,
                timeRange: selectedRange
            )
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Estadísticas
            HStack {
                ChartStatisticsView(readings: readings, metric: selectedMetric)
                Spacer()
                Text("Última actualización: \(lastUpdateText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    // MARK: - Computed Properties

    private var lastUpdateText: String {
        guard let newest = readings.last?.timestamp else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: newest, relativeTo: Date())
    }

    // MARK: - Actions

    private func loadData() {
        guard appState.isHistoryEnabled else {
            readings = []
            monthlyStats = []
            return
        }

        isLoading = true

        Task {
            switch viewMode {
            case .chart:
                readings = await appState.fetchHistoryReadings(for: selectedRange)
            case .stats:
                monthlyStats = await appState.fetchMonthlyStats()
            }
            isLoading = false
        }
    }

    private func exportCurrentView() {
        guard !readings.isEmpty else { return }

        isExporting = true

        Task {
            // Generar CSV de los datos visibles
            let csv = generateCSV()

            await MainActor.run {
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.commaSeparatedText]
                savePanel.nameFieldStringValue = "qingping_\(selectedMetric.rawValue)_\(selectedRange.rawValue).csv"

                if savePanel.runModal() == .OK, let url = savePanel.url {
                    do {
                        try csv.write(to: url, atomically: true, encoding: .utf8)
                    } catch {
                        print("Error exportando: \(error)")
                    }
                }

                isExporting = false
            }
        }
    }

    private func generateCSV() -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        var csv = "timestamp,\(selectedMetric.rawValue)\n"

        for reading in readings {
            if let value = reading.value(for: selectedMetric) {
                let row = "\(dateFormatter.string(from: reading.timestamp)),\(value)"
                csv += row + "\n"
            }
        }

        return csv
    }
}

#Preview {
    HistoryWindowView()
        .environmentObject(AppState())
}
