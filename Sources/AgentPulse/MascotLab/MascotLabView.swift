import AgentPulseCore
import AppKit
import SwiftUI

/// Debug-окно: ручной запуск состояний и реакций, слайдеры `MascotTuning` вживую.
struct MascotLabView: View {
    @Bindable var model: PulseModel

    private static let states: [(String, MascotState?)] = [
        ("Живое (из событий)", nil),
        ("sleep", .sleep),
        ("idle", .idle),
        ("think", .think),
        ("work · read", .work(.read)),
        ("work · edit", .work(.edit)),
        ("work · run", .work(.run)),
        ("work · search", .work(.search)),
        ("work · общий", .work(.general)),
        ("wait_you · разрешение", .waitYou(.permission)),
        ("wait_you · вопрос", .waitYou(.input)),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 12) {
                MascotView(animator: model.animator, diameter: 96)
                    .background(Color(white: 0.92), in: RoundedRectangle(cornerRadius: 12))
                MascotView(animator: model.animator, diameter: 48)
                    .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 12))
                Text(model.visibleBubbleText ?? " ")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .padding()

            Form {
                Section("Состояние") {
                    Picker("Состояние", selection: $model.labOverride) {
                        ForEach(Self.states, id: \.0) { title, state in
                            Text(title).tag(state)
                        }
                    }
                    Toggle("Reduce Motion", isOn: $model.labReduceMotion)
                }
                Section("Реакции") {
                    HStack {
                        ForEach(MascotReaction.allCases, id: \.self) { reaction in
                            Button(reaction.rawValue) { model.playReaction(reaction) }
                        }
                    }
                }
                Section("Взгляд") {
                    slider("Жёсткость саккады ω", $model.tuning.saccadeOmega, 8...80)
                    slider("Радиус hover, pt", $model.tuning.hoverRadius, 40...300)
                    range("Фиксация idle, s", $model.tuning.idleFixation, 0.5...8)
                    range("Фиксация think, s", $model.tuning.thinkFixation, 0.5...6)
                    range("Фиксация work, s", $model.tuning.workFixation, 0.1...3)
                    slider("Строка чтения, s", $model.tuning.readLineDuration, 0.4...4)
                }
                Section("Моргание") {
                    slider("Закрытие, s", $model.tuning.blinkClose, 0.02...0.3)
                    slider("Открытие, s", $model.tuning.blinkOpen, 0.02...0.4)
                    range("Интервал, s", $model.tuning.blinkInterval, 0.5...12)
                    slider("Двойное, доля", $model.tuning.doubleBlinkChance, 0...1)
                }
                Section("Тело и свечение") {
                    slider("Подпрыгивание, pt", $model.tuning.hopHeight, 0...8)
                    slider("Радиус свечения", $model.tuning.glowRadius, 0...30)
                    slider("Яркость свечения", $model.tuning.glowOpacity, 0...1)
                }
                Section("Живость") {
                    slider("Растяжение в прыжке", $model.tuning.stretchPerSpeed, 0...0.006)
                    slider("Сплющивание при приземлении", $model.tuning.landingSquash, 0...0.2)
                    slider("Приседание перед прыжком, pt", $model.tuning.anticipation, 0...4)
                    slider("Дыхание тела", $model.tuning.breathAmount, 0...0.05)
                    slider("Микродвижения глаз", $model.tuning.microSaccade, 0...0.12)
                    slider("Наклон, когда думает", $model.tuning.thinkTilt, 0...0.4)
                }
                Section("Облачко") {
                    slider("Фон не чаще, s", $model.tuning.bubble.ambientInterval, 2...30)
                    slider("Модус держится, s", $model.tuning.bubble.ambientMinHold, 0...6)
                    slider("Мин. показ, s", $model.tuning.bubble.minShow, 0.2...3)
                }
                Section {
                    HStack {
                        Button("Сбросить") { model.tuning = MascotTuning() }
                        Button("Скопировать JSON") { copyTuning() }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 420)
        }
        .frame(minHeight: 560)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ bounds: ClosedRange<Double>) -> some View {
        LabeledContent {
            Slider(value: value, in: bounds)
        } label: {
            Text("\(title): \(value.wrappedValue, format: .number.precision(.fractionLength(2)))")
        }
    }

    private func range(_ title: String, _ value: Binding<ClosedRange<Double>>, _ bounds: ClosedRange<Double>) -> some View {
        let lower = Binding(
            get: { value.wrappedValue.lowerBound },
            set: { value.wrappedValue = $0...max($0, value.wrappedValue.upperBound) }
        )
        let upper = Binding(
            get: { value.wrappedValue.upperBound },
            set: { value.wrappedValue = min($0, value.wrappedValue.lowerBound)...$0 }
        )
        return VStack(alignment: .leading) {
            Text("\(title): \(lower.wrappedValue, format: .number.precision(.fractionLength(2)))…\(upper.wrappedValue, format: .number.precision(.fractionLength(2)))")
            Slider(value: lower, in: bounds)
            Slider(value: upper, in: bounds)
        }
    }

    private func copyTuning() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(model.tuning), let json = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }
}
