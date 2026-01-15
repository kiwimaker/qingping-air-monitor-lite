import SwiftUI
import Charts
import UniformTypeIdentifiers

struct HistoryWindowView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedMetric: SensorMetric = .co2
    @State private var selectedRange: TimeRange = .day
    @State private var readings: [SensorReading] = []
    @State private var isLoading = false
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
                .padding()
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            if !appState.isHistoryEnabled {
                historyDisabledView
            } else if isLoading {
                loadingView
            } else if readings.isEmpty {
                emptyView
            } else {
                chartContent
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear { loadData() }
        .onChange(of: selectedRange) { loadData() }
        .onChange(of: appState.selectedDeviceMac) { loadData() }
    }

    // MARK: - Subviews

    private var toolbar: some View {
        HStack {
            // Selector de métrica
            Picker("Métrica", selection: $selectedMetric) {
                ForEach(SensorMetric.allCases) { metric in
                    Text(metric.label).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 350)

            Spacer()

            // Selector de rango temporal
            Picker("Rango", selection: $selectedRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)

            // Botón sincronizar desde API
            Button {
                Task {
                    await appState.forceSyncHistory(days: 30)
                    loadData()
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
            .buttonStyle(.borderless)
            .help("Sincronizar últimos 30 días desde la nube")
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
            .disabled(readings.isEmpty || isExporting)
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
            return
        }

        isLoading = true

        Task {
            readings = await appState.fetchHistoryReadings(for: selectedRange)
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
