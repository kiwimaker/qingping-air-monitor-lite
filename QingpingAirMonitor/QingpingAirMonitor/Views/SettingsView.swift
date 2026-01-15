import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var clientId: String = ""
    @State private var clientSecret: String = ""
    @State private var refreshInterval: Double = 60
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var hasExistingCredentials = false
    @State private var isSaving = false

    // History states
    @State private var historyRecordCount: Int = 0
    @State private var historyDatabaseSize: Int64 = 0
    @State private var historyOldestDate: Date?
    @State private var historyNewestDate: Date?
    @State private var showDeleteConfirmation = false
    @State private var isExporting = false

    var body: some View {
        TabView {
            credentialsTab
                .tabItem {
                    Label("API", systemImage: "key")
                }

            displayTab
                .tabItem {
                    Label("Pantalla", systemImage: "menubar.rectangle")
                }

            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            historyTab
                .tabItem {
                    Label("Histórico", systemImage: "chart.line.uptrend.xyaxis")
                }

            aboutTab
                .tabItem {
                    Label("Acerca de", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 380)
        .onAppear(perform: loadExistingSettings)
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Credentials Tab

    private var credentialsTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Credenciales de API")
                        .font(.headline)

                    Text("Obtén tus credenciales en el portal de desarrollador de Qingping")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Link("Abrir developer.qingping.co",
                         destination: URL(string: "https://developer.qingping.co")!)
                        .font(.caption)
                }
                .padding(.bottom, 8)

                TextField("App Key (Client ID)", text: $clientId)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: clientId) { _, newValue in
                        // Validar: solo caracteres alfanuméricos, guiones y guiones bajos
                        let filtered = newValue.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                        if filtered != newValue {
                            clientId = filtered
                        }
                    }

                SecureField("App Secret (Client Secret)", text: $clientSecret)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: clientSecret) { _, newValue in
                        // No filtrar el placeholder
                        guard newValue != "••••••••••••••••" else { return }
                        // Validar: solo caracteres alfanuméricos y símbolos seguros
                        let filtered = newValue.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
                        if filtered != newValue {
                            clientSecret = filtered
                        }
                    }

                HStack {
                    if hasExistingCredentials {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Credenciales guardadas")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Borrar") {
                        clearCredentials()
                    }
                    .disabled(!hasExistingCredentials)

                    Button {
                        saveCredentials()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 60)
                        } else {
                            Text("Guardar")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(clientId.isEmpty || clientSecret.isEmpty || isSaving)
                }
            }
        }
        .padding()
    }

    // MARK: - Display Tab

    private var displayTab: some View {
        Form {
            Section {
                Text("Mostrar en la barra de menú")
                    .font(.headline)

                Text("Selecciona qué valores se mostrarán junto al icono")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Temperatura", isOn: $appState.menuBarDisplayOptions.showTemperature)
                Toggle("Humedad", isOn: $appState.menuBarDisplayOptions.showHumidity)
                Toggle("CO₂", isOn: $appState.menuBarDisplayOptions.showCO2)
                Toggle("PM2.5", isOn: $appState.menuBarDisplayOptions.showPM25)
                Toggle("PM10", isOn: $appState.menuBarDisplayOptions.showPM10)
            }

            Section {
                HStack {
                    Text("Vista previa:")
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "aqi.medium")
                        if let data = appState.currentData {
                            Text(data.displayText(options: appState.menuBarDisplayOptions))
                                .font(.system(.body, design: .rounded))
                        } else {
                            Text("—")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                }
            }
        }
        .padding()
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Text("Intervalo de actualización")
                    .font(.headline)

                Text("El dispositivo sube datos cada 15 min por defecto (configurable en Qingping IoT)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Actualizar cada", selection: $refreshInterval) {
                    Text("1 min").tag(60.0)
                    Text("5 min").tag(300.0)
                    Text("15 min").tag(900.0)
                    Text("30 min").tag(1800.0)
                }
                .pickerStyle(.segmented)
                .onChange(of: refreshInterval) {
                    appState.updateRefreshInterval(refreshInterval)
                }
            }

            Section {
                Text("Estado de conexión")
                    .font(.headline)

                HStack {
                    Circle()
                        .fill(appState.connectionStatus.color)
                        .frame(width: 10, height: 10)
                    Text(appState.connectionStatus.description)
                        .foregroundColor(.secondary)

                    Spacer()

                    if appState.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                if let error = appState.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
    }

    // MARK: - History Tab

    private var historyTab: some View {
        Form {
            Section {
                Toggle("Guardar histórico de datos", isOn: $appState.isHistoryEnabled)

                Text("Los datos se guardarán cada vez que se actualicen según el intervalo configurado")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if appState.isHistoryEnabled {
                Section {
                    Picker("Retención máxima", selection: $appState.historyRetention) {
                        ForEach(HistoryRetention.allCases) { retention in
                            Text(retention.label).tag(retention)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Los datos más antiguos se eliminarán automáticamente")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    LabeledContent("Registros almacenados") {
                        Text("\(historyRecordCount)")
                            .monospacedDigit()
                    }

                    LabeledContent("Espacio usado") {
                        Text(formatBytes(historyDatabaseSize))
                            .monospacedDigit()
                    }

                    if let oldest = historyOldestDate, let newest = historyNewestDate {
                        LabeledContent("Rango de datos") {
                            Text("\(formatDate(oldest)) - \(formatDate(newest))")
                                .font(.caption)
                        }
                    }
                }

                Section {
                    HStack {
                        Button {
                            exportHistory()
                        } label: {
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Label("Exportar CSV", systemImage: "square.and.arrow.up")
                            }
                        }
                        .disabled(historyRecordCount == 0 || isExporting)

                        Spacer()

                        Button("Limpiar histórico", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .disabled(historyRecordCount == 0)
                    }
                }
            }
        }
        .padding()
        .onAppear { loadHistoryStats() }
        .confirmationDialog(
            "¿Eliminar todo el histórico?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                deleteHistory()
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Esta acción no se puede deshacer. Se eliminarán \(historyRecordCount) registros.")
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "aqi.medium")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Qingping Air Monitor")
                .font(.title2)
                .fontWeight(.semibold)

            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Monitor de calidad del aire para macOS")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 4) {
                Text("Compatible con Qingping Air Monitor Lite")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Link("Documentación de la API",
                     destination: URL(string: "https://developer.qingping.co")!)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadExistingSettings() {
        hasExistingCredentials = appState.keychainService.hasCredentials
        if let credentials = appState.keychainService.getCredentials() {
            clientId = credentials.clientId
            clientSecret = "••••••••••••••••"
        }
        refreshInterval = appState.refreshInterval
    }

    private func saveCredentials() {
        // Si el secret es el placeholder, no lo guardamos
        let secretToSave = clientSecret == "••••••••••••••••" ?
            (appState.keychainService.getCredentials()?.clientSecret ?? "") :
            clientSecret

        guard !secretToSave.isEmpty else {
            alertTitle = "Error"
            alertMessage = "Introduce el App Secret"
            showingAlert = true
            return
        }

        isSaving = true

        Task {
            do {
                try await appState.saveCredentials(clientId: clientId, clientSecret: secretToSave)
                hasExistingCredentials = true

                if appState.lastError == nil {
                    alertTitle = "Conectado"
                    alertMessage = "Credenciales válidas. Datos obtenidos correctamente."
                } else {
                    alertTitle = "Guardado con errores"
                    alertMessage = "Credenciales guardadas pero hubo un error: \(appState.lastError ?? "")"
                }
            } catch {
                alertTitle = "Error"
                alertMessage = "Error al guardar: \(error.localizedDescription)"
            }

            isSaving = false
            showingAlert = true
        }
    }

    private func clearCredentials() {
        appState.clearCredentials()
        clientId = ""
        clientSecret = ""
        hasExistingCredentials = false
        alertTitle = "Borrado"
        alertMessage = "Credenciales eliminadas"
        showingAlert = true
    }

    // MARK: - History Actions

    private func loadHistoryStats() {
        Task {
            let stats = await appState.getHistoryStats()
            historyRecordCount = stats.count
            historyDatabaseSize = stats.size
            historyOldestDate = stats.oldest
            historyNewestDate = stats.newest
        }
    }

    private func exportHistory() {
        isExporting = true

        Task {
            if let csvContent = await appState.exportHistoryToCSV() {
                // Mostrar diálogo de guardar
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.commaSeparatedText]
                savePanel.nameFieldStringValue = "qingping_history_\(Date().timeIntervalSince1970).csv"

                if savePanel.runModal() == .OK, let url = savePanel.url {
                    do {
                        try csvContent.write(to: url, atomically: true, encoding: .utf8)
                        alertTitle = "Exportado"
                        alertMessage = "Histórico exportado correctamente"
                    } catch {
                        alertTitle = "Error"
                        alertMessage = "Error al guardar: \(error.localizedDescription)"
                    }
                    showingAlert = true
                }
            } else {
                alertTitle = "Error"
                alertMessage = "No hay datos para exportar"
                showingAlert = true
            }

            isExporting = false
        }
    }

    private func deleteHistory() {
        Task {
            await appState.deleteAllHistory()
            loadHistoryStats()
            alertTitle = "Eliminado"
            alertMessage = "Histórico eliminado correctamente"
            showingAlert = true
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
