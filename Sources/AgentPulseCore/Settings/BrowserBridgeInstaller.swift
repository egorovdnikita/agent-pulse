import CryptoKit
import Foundation

/// Регистрирует `pulse-hook` как native messaging host для Chromium-браузеров.
/// Пишет по одному JSON-манифесту в каталог `NativeMessagingHosts` каждого установленного браузера.
public enum BrowserBridgeInstaller {
    public static let hostName = "io.github.egorovdnikita.agentpulse"
    /// ID распакованного расширения из `Extensions/Chrome` (задан ключом в manifest.json).
    public static let extensionId = "fjodifilhedcelmlkblmbdffgihjdonl"

    /// Каталоги профилей Chromium-браузеров относительно Application Support.
    static let browsers = [
        "Google/Chrome", "Google/Chrome Beta", "Google/Chrome Canary", "Chromium",
        "BraveSoftware/Brave-Browser", "Microsoft Edge", "Arc/User Data", "Vivaldi",
    ]

    public static var applicationSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    static func manifestURLs(applicationSupport: URL) -> [URL] {
        browsers
            .map { applicationSupport.appending(path: $0, directoryHint: .isDirectory) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { $0.appending(path: "NativeMessagingHosts/\(hostName).json") }
    }

    public static func manifest(hookPath: String) -> [String: Any] {
        [
            "name": hostName,
            "description": "Agent Pulse: состояние Claude в браузере",
            "path": hookPath,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionId)/"],
        ]
    }

    /// Возвращает установленные манифесты.
    @discardableResult
    public static func install(hookPath: String, applicationSupport: URL = applicationSupport) throws -> [URL] {
        let data = try JSONSerialization.data(
            withJSONObject: manifest(hookPath: hookPath), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let urls = manifestURLs(applicationSupport: applicationSupport)
        for url in urls {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        return urls
    }

    public static func uninstall(applicationSupport: URL = applicationSupport) throws {
        for url in manifestURLs(applicationSupport: applicationSupport) where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Мост установлен, но указывает на другой `pulse-hook`.
    public static func needsUpdate(hookPath: String, applicationSupport: URL = applicationSupport) -> Bool {
        manifestURLs(applicationSupport: applicationSupport).contains { url in
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return manifest["path"] as? String != hookPath
        }
    }

    public static func isInstalled(applicationSupport: URL = applicationSupport) -> Bool {
        manifestURLs(applicationSupport: applicationSupport).contains { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// ID расширения Chrome из публичного ключа: первые 128 бит SHA-256, цифры 0–f → буквы a–p.
public enum ChromeExtensionId {
    public static func from(publicKey: Data) -> String {
        let digest = Array(SHA256.hash(data: publicKey))
        return digest.prefix(16).flatMap { [$0 >> 4, $0 & 0x0F] }
            .map { String(UnicodeScalar(UInt8(ascii: "a") + $0)) }
            .joined()
    }
}
