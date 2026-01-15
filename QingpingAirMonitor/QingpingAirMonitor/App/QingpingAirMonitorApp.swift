import SwiftUI
import AppKit

// Punto de entrada manual usando AppKit puro
@main
enum AppMain {
    // Mantener una referencia fuerte al delegate para evitar que se desasigne
    static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared

        // Configurar el delegate
        let delegate = AppDelegate()
        AppMain.delegate = delegate
        app.delegate = delegate

        // Ejecutar la aplicación
        // No llamamos setupStatusItem aquí, dejamos que applicationDidFinishLaunching lo maneje
        app.run()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 applicationDidFinishLaunching")
        
        // Aseguramos que la UI se cree en el siguiente ciclo del RunLoop
        // para evitar condiciones de carrera con el sistema de ventanas
        setupStatusItem()
        
        // Iniciar refresco de datos si está configurado
        if appState.isConfigured {
            print("🔄 Iniciando refresco periódico...")
            appState.startPeriodicRefresh()
        }
    }

    func setupStatusItem() {
        print("🟢 Configurando status item...")

        // Crear el status item
        // Usamos una referencia fuerte a statusItem
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = " Air"
            button.image = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: "Air Quality")
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover(_:))
            button.target = self
            print("✅ Status item creado: \(String(describing: statusItem))")
        }

        // Crear el popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView().environmentObject(appState)
        )
        self.popover = popover

        print("✅ Setup completado")
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Activar la app para que reciba eventos de teclado si es necesario,
            // aunque para un popover de menu bar a veces no se desea robar el foco completamente.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func openSettings(_ sender: AnyObject?) {
        // Asegurarse de que SettingsView existe y está disponible
        let settingsView = SettingsView().environmentObject(appState)
        
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "Ajustes"
        settingsWindow.contentViewController = NSHostingController(rootView: settingsView)
        settingsWindow.center()
        settingsWindow.isReleasedWhenClosed = false // Importante para que no crashee al cerrar y reabrir si se gestiona mal
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}