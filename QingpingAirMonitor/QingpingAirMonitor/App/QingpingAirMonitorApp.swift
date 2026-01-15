import SwiftUI
import AppKit

// Punto de entrada manual usando AppKit puro
@main
enum AppMain {
    static func main() {
        let app = NSApplication.shared

        // Ejecutar en el MainActor
        MainActor.assumeIsolated {
            let delegate = AppDelegate()
            app.delegate = delegate

            // Crear el status item ANTES de ejecutar el app
            delegate.setupStatusItem()
        }

        // Ejecutar la aplicación
        app.run()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let appState = AppState()

    func setupStatusItem() {
        print("🟢 Creando status item ANTES de app.run()...")

        // Configurar como app accesoria (sin dock)
        NSApp.setActivationPolicy(.accessory)

        // Crear el status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = " Air"
            button.image = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: "Air Quality")
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover(_:))
            button.target = self
            print("✅ Status item creado: \(statusItem!)")
            print("✅ Button: frame=\(button.frame), isHidden=\(button.isHidden)")
        }

        statusItem.isVisible = true

        // Crear el popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView().environmentObject(appState)
        )

        print("✅ Setup completado")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 applicationDidFinishLaunching")
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func openSettings(_ sender: AnyObject?) {
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "Ajustes"
        settingsWindow.contentViewController = NSHostingController(
            rootView: SettingsView().environmentObject(appState)
        )
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
