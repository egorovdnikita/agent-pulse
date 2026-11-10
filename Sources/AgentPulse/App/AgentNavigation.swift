import AgentPulseCore
import AppKit

/// Только явный клик: известная веб-сессия либо приложение-источник.
@MainActor
enum AgentNavigation {
    static func open(source: AgentEvent.Source?, sessionID: String?, host: String?) {
        if let source, let sessionID, let destination = AgentDestination.webURL(source: source, sessionID: sessionID) {
            let browsers: Set<String> = ["com.google.Chrome", "com.google.Chrome.canary", "com.microsoft.edgemac", "com.apple.Safari", "com.brave.Browser", "company.thebrowser.Browser"]
            if let host, browsers.contains(host), let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: host) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.open([destination], withApplicationAt: app, configuration: config)
            } else { NSWorkspace.shared.open(destination) }
            return
        }
        if let host { NSRunningApplication.runningApplications(withBundleIdentifier: host).first?.activate() }
    }
}
