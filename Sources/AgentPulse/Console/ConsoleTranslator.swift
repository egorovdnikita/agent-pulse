import AgentPulseCore
import Foundation
#if canImport(Translation)
import Translation
#endif

/// Перевод на устройстве, macOS 26+. Текст остаётся на этом Mac.
enum ConsoleTranslator {
    static var isAvailable: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    static let needsLanguages = "Скачай языки: Системные настройки → Основные → Язык и регион → Языки перевода"

    /// Возвращает перевод. Ошибка — текст для вкладки.
    static func translate(_ text: String) async -> Result<String, TranslateProblem> {
        #if canImport(Translation)
        if #available(macOS 26, *) {
            let direction = TranslateDirection.detect(text)
            let source = Locale.Language(identifier: direction.source)
            let target = Locale.Language(identifier: direction.target)
            guard await LanguageAvailability().status(from: source, to: target) == .installed else {
                return .failure(TranslateProblem(text: needsLanguages))
            }
            do {
                let session = TranslationSession(installedSource: source, target: target)
                return .success(try await session.translate(text).targetText)
            } catch {
                return .failure(TranslateProblem(text: "Не удалось перевести"))
            }
        }
        #endif
        return .failure(TranslateProblem(text: "Перевод работает на macOS 26 и новее"))
    }
}

struct TranslateProblem: Error {
    let text: String
}
