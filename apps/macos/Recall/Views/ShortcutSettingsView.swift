import SwiftUI

struct ShortcutSettingsView: View {
    @EnvironmentObject private var shortcutCenter: GlobalShortcutCenter
    @State private var draft = GlobalShortcutConfiguration.default
    @State private var didApply = false

    var body: some View {
        Form {
            Section {
                shortcutEditor(for: .screenshot)
                Divider()
                shortcutEditor(for: .clipboard)
            } header: {
                Text("Global capture shortcuts")
            } footer: {
                Text(
                    "Shortcuts work while Recall is running, even when its main window "
                        + "is closed. Each enabled shortcut needs at least two modifier keys. "
                        + "Letter and number choices use their physical U.S. keyboard positions."
                )
            }

            if let errorMessage = shortcutCenter.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if didApply && draft == shortcutCenter.configuration {
                Section {
                    Label("Shortcuts are active.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            HStack {
                Button("Restore Defaults") {
                    if shortcutCenter.restoreDefaults() {
                        draft = shortcutCenter.configuration
                        didApply = true
                    }
                }
                Spacer()
                Button("Apply") {
                    didApply = shortcutCenter.apply(draft)
                    if didApply {
                        draft = shortcutCenter.configuration
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
        .onAppear {
            draft = shortcutCenter.configuration
        }
        .onChange(of: shortcutCenter.configuration) {
            draft = shortcutCenter.configuration
        }
    }

    private func shortcutEditor(for action: GlobalShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(action.displayName, isOn: enabledBinding(for: action))
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(ShortcutModifierChoice.allCases) { choice in
                    Toggle(choice.symbol, isOn: modifierBinding(choice, for: action))
                        .toggleStyle(.button)
                        .help(choice.name)
                }

                Picker("Key", selection: keyBinding(for: action)) {
                    ForEach(GlobalShortcutKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
            }
            .disabled(!draft[action].isEnabled)

            Text(
                draft[action].isEnabled
                    ? draft[action].displayName
                    : "Off"
            )
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func enabledBinding(for action: GlobalShortcutAction) -> Binding<Bool> {
        Binding(
            get: { draft[action].isEnabled },
            set: { draft[action].isEnabled = $0 }
        )
    }

    private func keyBinding(for action: GlobalShortcutAction) -> Binding<GlobalShortcutKey> {
        Binding(
            get: { draft[action].key },
            set: { draft[action].key = $0 }
        )
    }

    private func modifierBinding(
        _ choice: ShortcutModifierChoice,
        for action: GlobalShortcutAction
    ) -> Binding<Bool> {
        Binding(
            get: { draft[action].modifiers.contains(choice.modifier) },
            set: { isEnabled in
                if isEnabled {
                    draft[action].modifiers.insert(choice.modifier)
                } else {
                    draft[action].modifiers.remove(choice.modifier)
                }
            }
        )
    }
}

private enum ShortcutModifierChoice: CaseIterable, Identifiable {
    case control
    case option
    case shift
    case command

    var id: Self { self }

    var modifier: GlobalShortcutModifiers {
        switch self {
        case .control: .control
        case .option: .option
        case .shift: .shift
        case .command: .command
        }
    }

    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    var name: String {
        switch self {
        case .control: "Control"
        case .option: "Option"
        case .shift: "Shift"
        case .command: "Command"
        }
    }
}
