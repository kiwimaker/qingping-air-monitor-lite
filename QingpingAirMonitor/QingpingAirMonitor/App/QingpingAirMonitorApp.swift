import SwiftUI
import AppKit

// Singleton para mantener el status item vivo
final class StatusBarController {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var appState: AppState?

    private init() {}

    func setup(appState: AppState) {
        self.appState = appState

        // Crear status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else {
            print("ERROR: No se pudo crear el botón del status item")
            return
        }

        // Configurar botón con texto simple
        button.title = " Air"
        button.image = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: "Air Quality")
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover)

        print("Status item creado correctamente")

        // Crear popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 280, height: 400)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarView().environmentObject(appState)
        )
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct QingpingAirMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("applicationDidFinishLaunching llamado")

        // Configurar como app accesoria (sin dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Crear el status bar item
        StatusBarController.shared.setup(appState: appState)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
