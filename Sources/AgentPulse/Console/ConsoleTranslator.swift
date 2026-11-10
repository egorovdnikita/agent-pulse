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

    static func supportedLanguages() async -> [String] {
        #if canImport(Translation)
        if #available(macOS 26, *) {
            return await LanguageAvailability().supportedLanguages.map(\.minimalIdentifier)
                .sorted { TranslateDirection.languageTitle($0) < TranslateDirection.languageTitle($1) }
        }
        #endif
        return ["en", "ru", "de"]
    }

    static func languagesReady(direction: TranslateDirection = .ruToEn) async -> Bool {
        if direction.source == direction.target { return true }
        #if canImport(Translation)
        if #available(macOS 26, *) {
            let russian = Locale.Language(identifier: direction.source)
            let english = Locale.Language(identifier: direction.target)
            return await LanguageAvailability().status(from: russian, to: english) == .installed
        }
        #endif
        return false
    }

    /// Возвращает перевод. Ошибка — текст для вкладки.
    static func translate(_ text: String, direction: TranslateDirection, protectedTerms: [String] = []) async -> Result<String, TranslateProblem> {
        if direction.source == direction.target { return .success(text) }
        let layout = TranslationLayout(text, protectedTerms: protectedTerms)
        if layout.texts.isEmpty { return .success(text) }
        #if canImport(Translation)
        if #available(macOS 26, *) {
            let source = Locale.Language(identifier: direction.source)
            let target = Locale.Language(identifier: direction.target)
            let status = await LanguageAvailability().status(from: source, to: target)
            guard status != .unsupported else { return .failure(TranslateProblem(text: "Эта пара языков пока не поддерживается macOS")) }
            guard status == .installed else {
                return .failure(TranslateProblem(text: needsLanguages))
            }
            do {
                let session = TranslationSession(installedSource: source, target: target)
                try Task.checkCancellation()
                let requests = layout.texts.enumerated().map {
                    TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
                }
                let responses = try await session.translations(from: requests)
                try Task.checkCancellation()
                var parts: [String: String] = [:]
                for response in responses {
                    if let id = response.clientIdentifier { parts[id] = response.targetText }
                }
                let ordered = layout.texts.indices.compactMap { parts[String($0)] }
                guard let result = layout.assembling(ordered) else {
                    return .failure(TranslateProblem(text: "Не удалось сохранить структуру перевода"))
                }
                return .success(result)
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
    var direction: TranslateDirection = .ruToEn
    private let ready = State<Bool?>(initialValue: nil)
    private let asking = State(initialValue: false)

    var body: some View {
        if #available(macOS 26, *) {
            LabeledContent("Языки") {
                switch ready.wrappedValue {
                case .some(true): Text(direction.title + " · готовы")
                case .some(false): TranslatorDownload(direction: direction, finished: { refresh() })
                case nil: Text("Проверяю…")
                }
            }
            // Система качает языки в фоне и не сообщает о конце: пока их нет, статус перечитывается сам.
            .task(id: direction) {
                ready.wrappedValue = nil
                while !Task.isCancelled {
                    let found = await ConsoleTranslator.languagesReady(direction: direction)
                    guard !Task.isCancelled else { return }
                    ready.wrappedValue = found
                    if found { return }
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    private func refresh() {
        Task { ready.wrappedValue = await ConsoleTranslator.languagesReady(direction: direction) }
    }
}

@available(macOS 26, *)
struct TranslatorDownload: View {
    var direction: TranslateDirection = .ruToEn
    let finished: @MainActor () -> Void
    private let request = State<TranslationSession.Configuration?>(initialValue: nil)

    var body: some View {
        Button("Скачать") {
            request.wrappedValue = TranslationSession.Configuration(
                source: Locale.Language(identifier: direction.source), target: Locale.Language(identifier: direction.target)
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
