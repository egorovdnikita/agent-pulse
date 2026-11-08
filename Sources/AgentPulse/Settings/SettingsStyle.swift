import AppKit
import SwiftUI

/// Настройки на системных элементах macOS: `Form` в сгруппированном стиле, системные цвета и шрифты.
/// Здесь только короткие имена, чтобы страницы не повторяли одно и то же.
enum SettingsStyle {
    static let text = Color.primary
    static let muted = Color.secondary
    static let destructive = Color.red
    static let track = Color(nsColor: .quaternaryLabelColor)

    static let body = Font.body
    static let bodyMedium = Font.body.weight(.medium)
    static let caption = Font.caption
}

private struct SettingsAnchorKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Блок настроек, к которому надо перейти.
    var settingsAnchor: String? {
        get { self[SettingsAnchorKey.self] }
        set { self[SettingsAnchorKey.self] = newValue }
    }
}

/// Страница: системная сгруппированная форма. Умеет сразу показать нужный блок.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.settingsAnchor) private var anchor

    var body: some View {
        ScrollViewReader { proxy in
            Form { content }
                .formStyle(.grouped)
                .onAppear { reveal(proxy) }
                .onChange(of: anchor) { reveal(proxy) }
        }
    }

    private func reveal(_ proxy: ScrollViewProxy) {
        guard let anchor else { return }
        DispatchQueue.main.async { proxy.scrollTo(anchor, anchor: .top) }
    }
}

/// Группа: системная секция с заголовком и примечанием.
struct SettingsBlock<Content: View>: View {
    let title: String?
    let footnote: String?
    let content: Content

    init(_ title: String? = nil, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            if let title { Text(title) }
        } footer: {
            if let footnote {
                Text(footnote).font(.caption).foregroundStyle(.secondary)
            }
        }
        .id(title)
    }
}

/// Системный выбор из списка.
struct SettingsPicker<Value: Hashable, Items: View>: View {
    let title: String
    let selection: Binding<Value>
    @ViewBuilder let items: Items

    init(_ title: String, selection: Binding<Value>, @ViewBuilder content: () -> Items) {
        self.title = title
        self.selection = selection
        items = content()
    }

    var body: some View {
        Picker(title, selection: selection) { items }
    }
}

/// Переключатель Пульта: зелёный, как шкалы. В настройках — системный.
struct ConsoleSwitch: View {
    let isOn: Bool
    var on = ConsoleStyle.green
    var off = ConsoleStyle.track
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(isOn ? on : off)
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                    .frame(width: 16, height: 16)
                    .padding(2)
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.75), value: isOn)
    }
}

/// Строка с клавишами, как в системных настройках клавиатуры.
struct ShortcutRow: View {
    let title: String
    let keys: String?
    /// Клавишу занял кто-то другой.
    var busy = false

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                if busy { Text("Занята другим приложением").foregroundStyle(.red) }
                Text(keys ?? "Нет").foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

/// Модуль: системная секция. Первая строка включает его, остальные видны, пока он включён.
struct ModuleCard<Options: View>: View {
    let title: String
    let summary: String
    let icon: String
    var tint: Color = Color(nsColor: .systemGray)
    let isOn: Bool
    let toggle: (Bool) -> Void
    @ViewBuilder let options: Options

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { isOn }, set: toggle)) {
                HStack(alignment: .center, spacing: 10) {
                    SettingsIcon(name: icon, tint: tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if isOn { options }
        }
        .id(title)
    }
}

/// Значок как в Системных настройках: белый системный символ на цветной скруглённой плашке.
struct SettingsIcon: View {
    let name: String
    var tint: Color = Color(nsColor: .systemGray)
    var size = 20.0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        // Как у Системных настроек: контурный белый символ, плашка светлее сверху, тонкая светлая окантовка.
        Image(systemName: name)
            // Знак 15 pt на плашке 20 pt — как у Системных настроек (замер их колонки).
            .font(.system(size: size * 0.72, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                ZStack {
                    shape.fill(tint)
                    shape.fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// Строка в модуле — обычная строка формы.
struct ModuleOption<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View { content }
}
