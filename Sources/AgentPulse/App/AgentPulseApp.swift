import AgentPulseCore
import SwiftUI

/// Menu bar приложение без иконки в Dock (LSUIElement в Info.plist; без бандла — `.accessory` в делегате).
@main
struct AgentPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var app

    var body: some Scene {
        MenuBarExtra {
            PulseMenuView(app: app) { NSApp.keyWindow?.close() }
        } label: {
            Image(systemName: app.model.menuSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
