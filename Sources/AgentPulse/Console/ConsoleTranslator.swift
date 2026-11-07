import AgentPulseCore
import AppKit
import Foundation
import SwiftUI
#if canImport(Translation)
@preconcurrency import Translation
#endif

/// Перевод на устройстве, macOS 26+. Текст остаётся на этом Mac.
enum ConsoleTranslator {
    static var isAvailable: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    static let needsLanguages = "Нужны языки перевода: они скачиваются один раз и работают без сети"

    static func languagesReady() async -> Bool {
        #if canImport(Translation)
        if #available(macOS 26, *) {
            let russian = Locale.Language(identifier: "ru")
            let english = Locale.Language(identifier: "en")
            return await LanguageAvailability().status(from: russian, to: english) == .installed
        }
        #endif
        return false
    }

    /// Возвращает перевод. Ошибка — текст для вкладки.
    static func translate(_ text: String, direction: TranslateDirection) async -> Result<String, TranslateProblem> {
        #if canImport(Translation)
        if #available(macOS 26, *) {
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

/// Статус языков в настройках и загрузка через системное окно.
struct TranslatorLanguagesRow: View {
    private let ready = State<Bool?>(initialValue: nil)
    private let asking = State(initialValue: false)

    var body: some View {
        if #available(macOS 26, *) {
            LabeledContent("Языки") {
                switch ready.wrappedValue {
                case .some(true): Text("Русский и английский готовы")
                case .some(false): TranslatorDownload(finished: { refresh() })
                case nil: Text("Проверяю…")
                }
            }
            // Система качает языки в фоне и не сообщает о конце: пока их нет, статус перечитывается сам.
            .task {
                while !Task.isCancelled {
                    let found = await ConsoleTranslator.languagesReady()
                    ready.wrappedValue = found
                    if found { return }
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    private func refresh() {
        Task { ready.wrappedValue = await ConsoleTranslator.languagesReady() }
    }
}

@available(macOS 26, *)
private struct TranslatorDownload: View {
    let finished: @MainActor () -> Void
    private let request = State<TranslationSession.Configuration?>(initialValue: nil)

    var body: some View {
        Button("Скачать") {
            request.wrappedValue = TranslationSession.Configuration(
                source: Locale.Language(identifier: "ru"), target: Locale.Language(identifier: "en")
            )
        }
        .translationTask(request.wrappedValue) { session in
            try? await session.prepareTranslation()
            await finished()
        }
    }
}

struct TranslateProblem: Error {
    let text: String
}
