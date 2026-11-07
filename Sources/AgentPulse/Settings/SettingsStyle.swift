import AppKit
import SwiftUI

/// Настройки на языке Пульта: Geist, спокойная палитра для светлой и тёмной темы. Значения — из CapaTheNotch (MIT).
enum SettingsStyle {
    static let window = dynamic(light: 0xFAFAFA, dark: 0x171717)
    static let sidebar = dynamic(light: 0xF4F4F5, dark: 0x1E1E1E)
    static let selection = dynamic(light: 0xE5E5E5, dark: 0x2C2C2C)
    static let hover = dynamic(light: 0xF4F4F5, dark: 0x2C2C2C)
    static let control = dynamic(light: 0xFFFFFF, dark: 0x333333)
    static let text = dynamic(light: 0x171717, dark: 0xF5F5F5)
    static let muted = dynamic(light: 0x737373, dark: 0xA3A3A3)
    static let icon = dynamic(light: 0x525252, dark: 0xA3A3A3)
    static let switchOff = dynamic(light: 0xE5E5E5, dark: 0x404040)
    static let accent = Color(hex: 0x6B97FF)
    static let ring = Color(nsColor: NSColor(name: nil) { appearance in
        (isDark(appearance) ? NSColor.white : NSColor.black).withAlphaComponent(0x0F / 255)
    })

    static let sidebarWidth = 200.0

    static let title = ConsoleStyle.font(22, .semibold)
    static let body = ConsoleStyle.font(13)
    static let bodyMedium = ConsoleStyle.font(13, .medium)
    static let caption = ConsoleStyle.font(12)

    static func spring(reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.75)
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = isDark(appearance) ? dark : light
            return NSColor(
                srgbRed: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255, alpha: 1
            )
        })
    }
}

/// Переключатель 34 × 20. Подпись остаётся столбцом: название и пояснение.
struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsSwitch(configuration: configuration)
    }
}

private struct SettingsSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) { configuration.label }
                .frame(maxWidth: .infinity, alignment: .leading)
            Capsule()
                .fill(configuration.isOn ? SettingsStyle.accent : SettingsStyle.switchOff)
                .frame(width: 34, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                        .frame(width: 16, height: 16)
                        .padding(2)
                }
                .animation(SettingsStyle.spring(reduced: reduceMotion), value: configuration.isOn)
        }
        .opacity(isEnabled ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "Включено" : "Выключено")
        .accessibilityAction { if isEnabled { configuration.isOn.toggle() } }
    }
}

/// Кнопка настроек: спокойная, с тонким краем.
struct SettingsButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SettingsStyle.body)
            .foregroundStyle(SettingsStyle.text)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? SettingsStyle.selection : SettingsStyle.control)
                    .shadow(color: SettingsStyle.ring, radius: 1, y: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(SettingsStyle.ring, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Строка боковой колонки.
struct SettingsSidebarItem: View {
    let tab: SettingsNavigation.Tab
    let number: Int
    let isSelected: Bool
    let highlight: Namespace.ID
    let action: () -> Void

    // Обычный @State без Xcode недоступен: его макрос лежит только там.
    private let hovering = State(initialValue: false)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(nsImage: SolarIcons.image(tab.icon) ?? NSImage())
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(isSelected ? SettingsStyle.text : SettingsStyle.icon)
                Text(tab.title)
                    .font(isSelected ? SettingsStyle.bodyMedium : SettingsStyle.body)
                    .foregroundStyle(SettingsStyle.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("⌘\(number)")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsStyle.muted)
                    .opacity(isSelected || hovering.wrappedValue ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SettingsStyle.selection)
                        .matchedGeometryEffect(id: "selection", in: highlight)
                } else if hovering.wrappedValue {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SettingsStyle.hover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering.wrappedValue = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering.wrappedValue)
        .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
