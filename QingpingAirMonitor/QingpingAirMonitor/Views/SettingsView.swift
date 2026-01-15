import SwiftUI

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

    var body: some View {
        TabView {
            credentialsTab
                .tabItem {
                    Label("API", systemImage: "key")
                }

            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            aboutTab
                .tabItem {
                    Label("Acerca de", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 280)
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

                SecureField("App Secret (Client Secret)", text: $clientSecret)
                    .textFieldStyle(.roundedBorder)

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

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Text("Intervalo de actualización")
                    .font(.headline)

                Picker("Actualizar cada", selection: $refreshInterval) {
                    Text("30 segundos").tag(30.0)
                    Text("1 minuto").tag(60.0)
                    Text("5 minutos").tag(300.0)
                    Text("15 minutos").tag(900.0)
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

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "aqi.medium")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Qingping Air Monitor")
                .font(.title2)
                .fontWeight(.semibold)

            Text("v1.0.0")
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
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
