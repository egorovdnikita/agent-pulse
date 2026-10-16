import AgentPulseCore
import SwiftUI

/// Минимум настроек: два слайдера вместо двадцати переключателей, тихие часы, день рождения, органы чувств.
struct CharacterSettingsView: View {
    let app: AppDelegate
    @Bindable private var form = BirthdayForm()

    var body: some View {
        @Bindable var model = app.model
        Form {
            Section("Характер") {
                LabeledContent("Болтливость") {
                    Slider(value: $model.config.character.talkativeness, in: 0...1) { editing in
                        if !editing { model.applyCharacter() }
                    }
                }
                LabeledContent("Озорство") {
                    Slider(value: $model.config.character.mischief, in: 0...1) { editing in
                        if !editing { model.applyCharacter() }
                    }
                }
                Text("Озорство — до \(Int((model.config.character.mischief * 8).rounded())) приколов в день")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Тишина") {
                TextField("Тихие часы с", text: Binding(
                    get: { model.config.character.quietFrom ?? "" },
                    set: { model.config.character.quietFrom = $0.isEmpty ? nil : $0 }
                ))
                TextField("до", text: Binding(
                    get: { model.config.character.quietTo ?? "" },
                    set: { model.config.character.quietTo = $0.isEmpty ? nil : $0 }
                ))
                Text("Созвон, полный экран и тихие часы — облачко молчит, приколов нет. «Ждёт тебя» слышно всегда.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Прятаться при долгом простое", isOn: $model.config.character.hideWhenIdle)
                Stepper("Через \(model.config.character.hideAfterMinutes) мин", value: $model.config.character.hideAfterMinutes, in: 5...240, step: 5)
            }
            Section("День рождения") {
                Toggle("Знаю день рождения", isOn: $form.known)
                if form.known {
                    DatePicker("Дата", selection: $form.date, displayedComponents: .date)
                }
            }
            Section("Органы чувств") {
                Toggle("Агенты", isOn: $model.config.senses.agents)
                Toggle("Тело ноутбука", isOn: $model.config.senses.body)
                Toggle("Ритм и время", isOn: $model.config.senses.rhythm)
                Toggle("Звук", isOn: $model.config.senses.audio)
                Toggle("Эксперименты (угол крышки)", isOn: $model.config.senses.experimental)
            }
            Section("Память") {
                Text("Только счётчики дня — задачи, ошибки, перерывы, поглаживания. Хранится 30 дней на этом Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Забыть всё") { model.resetMemory() }
            }
            Section {
                Button("Сохранить") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear(perform: load)
    }

    private func load() {
        let model = app.model
        if let parts = model.config.character.birthday?.split(separator: "-"), parts.count == 2,
           let month = Int(parts[0]), let day = Int(parts[1]),
           let date = Calendar.current.date(from: DateComponents(year: 2000, month: month, day: day)) {
            form.date = date
            form.known = true
        }
    }

    private func save() {
        let model = app.model
        if form.known {
            let parts = Calendar.current.dateComponents([.month, .day], from: form.date)
            model.config.character.birthday = String(format: "%02d-%02d", parts.month ?? 1, parts.day ?? 1)
        } else {
            model.config.character.birthday = nil
        }
        model.applyCharacter()
        app.startSenses()
    }
}

@Observable
final class BirthdayForm {
    var known = false
    var date = Date()
}
