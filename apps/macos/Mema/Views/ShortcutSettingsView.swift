import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    @EnvironmentObject private var shortcutCenter: GlobalShortcutCenter
    @EnvironmentObject private var store: MemaStore
    @State private var draft = GlobalShortcutConfiguration.default
    @State private var didApply = false
    @State private var accessibilityAccessIsGranted = false
    @State private var isCheckingAccessibilityAccess = false

    var body: some View {
        TabView {
            shortcutsForm
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            privacyAndFeaturesForm
                .tabItem {
                    Label("Privacy & Features", systemImage: "hand.raised")
                }
        }
        .frame(width: 560, height: 620)
        .onAppear {
            draft = shortcutCenter.configuration
            refreshAccessibilityAccess()
        }
        .onChange(of: shortcutCenter.configuration) {
            draft = shortcutCenter.configuration
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refreshAccessibilityAccess()
        }
    }

    private var shortcutsForm: some View {
        Form {
            Section {
                shortcutEditor(for: .selection)
                Divider()
                shortcutEditor(for: .screenshot)
                Divider()
                shortcutEditor(for: .clipboard)
            } header: {
                Text("Global capture shortcuts")
            } footer: {
                Text(
                    "Shortcuts work while Mema is running, even when its main window "
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
                    Label("Shortcut settings saved.", systemImage: "checkmark.circle.fill")
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
                Button("Apply Shortcuts") {
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
        .padding(.vertical, 8)
    }

    private var privacyAndFeaturesForm: some View {
        Form {
            Section {
                HStack {
                    Label(
                        accessibilityAccessIsGranted
                            ? "Accessibility access is enabled"
                            : "Accessibility access is not enabled",
                        systemImage: accessibilityAccessIsGranted
                            ? "checkmark.shield.fill"
                            : "hand.raised.fill"
                    )
                    .foregroundStyle(accessibilityAccessIsGranted ? .green : .orange)
                    Spacer()
                    if isCheckingAccessibilityAccess {
                        ProgressView()
                            .controlSize(.small)
                    } else if accessibilityAccessIsGranted {
                        Button("Manage Access…") {
                            openAccessibilitySettings()
                        }
                    } else {
                        Button("Request Access") {
                            requestAccessibilityAccess()
                        }
                    }
                }
                Text(
                    "Accessibility permission is managed by macOS. Mema can request it "
                        + "or open System Settings, but cannot turn it off inside the app."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                Toggle(
                    "Clipboard Compatibility Mode",
                    isOn: Binding(
                        get: { store.selectionClipboardFallbackIsEnabled },
                        set: { store.setSelectionClipboardFallbackEnabled($0) }
                    )
                )
                Text(
                    "For apps such as WeChat that do not expose selected text or a focused "
                        + "control, Capture Selection can send Copy twice to the verified "
                        + "frontmost app, confirm matching results, and attempt to restore "
                        + "the previous clipboard."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Selection access")
            } footer: {
                Text(
                    "Mema reads selected text only when you use Capture Selection. "
                        + "Clipboard and screenshot capture do not use Accessibility access. "
                        + "Mema rejects secure input and protected controls when macOS "
                        + "exposes them, but custom-drawn apps may omit per-control safety "
                        + "attributes. "
                        + "macOS does not expose clipboard-writer identity or an atomic restore, "
                        + "so rare races or a very delayed Copy can still change the clipboard. "
                        + "Clipboard history apps and Universal Clipboard may record the "
                        + "temporary copies."
                )
            }

            Section {
                Toggle(
                    "Allow cloud AI analysis for image notes",
                    isOn: $store.imageAnalysisIsEnabled
                )
                Text(
                    "This is the master privacy control. When enabled, new image notes "
                        + "start with AI indexing on, and you can turn it off for one image "
                        + "before saving. Mema saves the original locally first, then sends "
                        + "enabled images to the configured GPT service for background OCR "
                        + "and visual understanding. Provider data policies apply."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Image notes")
            } footer: {
                Text(
                    "Turning this off blocks AI analysis for every new image note and disables "
                        + "the per-image control. Existing images and annotations are unchanged."
                )
            }

            Section {
                Label("Changes on this page are saved automatically.", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private func refreshAccessibilityAccess() {
        guard !isCheckingAccessibilityAccess else { return }
        isCheckingAccessibilityAccess = true
        Task { @MainActor in
            accessibilityAccessIsGranted = await store.accessibilityAccessIsGranted()
            isCheckingAccessibilityAccess = false
        }
    }

    private func requestAccessibilityAccess() {
        guard !isCheckingAccessibilityAccess else { return }
        isCheckingAccessibilityAccess = true
        Task { @MainActor in
            accessibilityAccessIsGranted = await store.accessibilityAccessIsGranted(
                promptIfNeeded: true
            )
            isCheckingAccessibilityAccess = false
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
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
