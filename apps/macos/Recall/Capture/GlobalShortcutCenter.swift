@preconcurrency import Carbon
import Combine
import Foundation

private let recallGlobalHotKeySignature: OSType = 0x52434C4C // "RCLL"

protocol GlobalShortcutRegistration: AnyObject {}

@MainActor
protocol GlobalShortcutRegistering: AnyObject {
    func register(
        _ shortcut: GlobalShortcut,
        handler: @escaping @MainActor @Sendable () -> Void
    ) throws -> any GlobalShortcutRegistration

    func unregister(_ registration: any GlobalShortcutRegistration)
}

@MainActor
final class GlobalShortcutCenter: ObservableObject {
    typealias ActionHandler = @MainActor @Sendable (GlobalShortcutAction) -> Void

    static let userDefaultsKey = "globalShortcutConfiguration.v1"

    @Published private(set) var configuration: GlobalShortcutConfiguration
    @Published private(set) var activeActions: Set<GlobalShortcutAction> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var registrationErrorMessage: String?

    private let userDefaults: UserDefaults
    private let registrar: any GlobalShortcutRegistering
    private let actionHandler: ActionHandler
    private var registrations: [GlobalShortcutAction: any GlobalShortcutRegistration] = [:]

    init(
        userDefaults: UserDefaults = .standard,
        registrar: (any GlobalShortcutRegistering)? = nil,
        actionHandler: @escaping ActionHandler = { _ in }
    ) {
        self.userDefaults = userDefaults
        self.registrar = registrar ?? CarbonGlobalShortcutRegistrar()
        self.actionHandler = actionHandler

        var initialConfiguration = GlobalShortcutConfiguration.default
        var initialMessage: String?
        var migratedLegacySelection = false
        if let storedData = userDefaults.data(forKey: Self.userDefaultsKey) {
            do {
                let needsSelectionMigration = !Self.containsSelectionShortcut(in: storedData)
                let storedConfiguration = try JSONDecoder().decode(
                    GlobalShortcutConfiguration.self,
                    from: storedData
                )
                try storedConfiguration.validate()
                initialConfiguration = storedConfiguration
                migratedLegacySelection = needsSelectionMigration
            } catch {
                initialMessage = "Saved shortcuts were invalid, so Recall restored its defaults."
                userDefaults.removeObject(forKey: Self.userDefaultsKey)
            }
        }

        configuration = initialConfiguration
        errorMessage = initialMessage
        registrationErrorMessage = nil

        do {
            registrations = try makeRegistrations(for: initialConfiguration)
            activeActions = Set(registrations.keys)
            if migratedLegacySelection,
               let migratedData = try? JSONEncoder().encode(initialConfiguration) {
                userDefaults.set(migratedData, forKey: Self.userDefaultsKey)
            }
        } catch let activationError as ShortcutActivationError
            where migratedLegacySelection
                && initialConfiguration.selection.isEnabled
                && activationError.action == .selection {
            var fallbackConfiguration = initialConfiguration
            fallbackConfiguration.selection.isEnabled = false
            do {
                registrations = try makeRegistrations(for: fallbackConfiguration)
                activeActions = Set(registrations.keys)
                configuration = fallbackConfiguration
                if let fallbackData = try? JSONEncoder().encode(fallbackConfiguration) {
                    userDefaults.set(fallbackData, forKey: Self.userDefaultsKey)
                }
                errorMessage = "Recall kept your existing shortcuts active, but the new "
                    + "Selection capture shortcut could not be registered. Choose another "
                    + "shortcut and enable it in Settings."
                registrationErrorMessage = nil
            } catch {
                registrations = [:]
                activeActions = []
                errorMessage = error.localizedDescription
                registrationErrorMessage = error.localizedDescription
            }
        } catch {
            registrations = [:]
            activeActions = []
            errorMessage = error.localizedDescription
            registrationErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func apply(_ proposedConfiguration: GlobalShortcutConfiguration) -> Bool {
        let encodedConfiguration: Data
        do {
            try proposedConfiguration.validate()
            encodedConfiguration = try JSONEncoder().encode(proposedConfiguration)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        let previousConfiguration = configuration
        unregisterAll(registrations)
        registrations = [:]
        activeActions = []

        do {
            let proposedRegistrations = try makeRegistrations(for: proposedConfiguration)
            registrations = proposedRegistrations
            activeActions = Set(proposedRegistrations.keys)
            configuration = proposedConfiguration
            userDefaults.set(encodedConfiguration, forKey: Self.userDefaultsKey)
            errorMessage = nil
            registrationErrorMessage = nil
            return true
        } catch {
            let applyError = error.localizedDescription
            do {
                let restoredRegistrations = try makeRegistrations(for: previousConfiguration)
                registrations = restoredRegistrations
                activeActions = Set(restoredRegistrations.keys)
                errorMessage = "\(applyError) Your previous shortcuts were restored."
                registrationErrorMessage = nil
            } catch {
                registrations = [:]
                activeActions = []
                errorMessage = "\(applyError) Recall also could not restore the previous "
                    + "shortcuts: \(error.localizedDescription)"
                registrationErrorMessage = errorMessage
            }
            return false
        }
    }

    @discardableResult
    func apply(_ shortcut: GlobalShortcut, for action: GlobalShortcutAction) -> Bool {
        var proposedConfiguration = configuration
        proposedConfiguration[action] = shortcut
        return apply(proposedConfiguration)
    }

    @discardableResult
    func setEnabled(_ isEnabled: Bool, for action: GlobalShortcutAction) -> Bool {
        var shortcut = configuration[action]
        shortcut.isEnabled = isEnabled
        return apply(shortcut, for: action)
    }

    @discardableResult
    func restoreDefaults() -> Bool {
        apply(.default)
    }

    @discardableResult
    func retryRegistration() -> Bool {
        apply(configuration)
    }

    func clearErrorMessage() {
        errorMessage = nil
    }

    func deactivate() {
        unregisterAll(registrations)
        registrations = [:]
        activeActions = []
    }

    private static func containsSelectionShortcut(in data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return false
        }
        return dictionary["selection"] != nil
    }

    private func makeRegistrations(
        for configuration: GlobalShortcutConfiguration
    ) throws -> [GlobalShortcutAction: any GlobalShortcutRegistration] {
        var result: [GlobalShortcutAction: any GlobalShortcutRegistration] = [:]

        do {
            for action in GlobalShortcutAction.allCases {
                let shortcut = configuration[action]
                guard shortcut.isEnabled else { continue }

                do {
                    result[action] = try registrar.register(shortcut) { [weak self] in
                        self?.actionHandler(action)
                    }
                } catch {
                    throw ShortcutActivationError(
                        action: action,
                        shortcut: shortcut,
                        reason: error.localizedDescription
                    )
                }
            }
        } catch {
            unregisterAll(result)
            throw error
        }

        return result
    }

    private func unregisterAll(
        _ registrations: [GlobalShortcutAction: any GlobalShortcutRegistration]
    ) {
        for action in GlobalShortcutAction.allCases {
            if let registration = registrations[action] {
                registrar.unregister(registration)
            }
        }
    }
}

private struct ShortcutActivationError: Error, LocalizedError {
    let action: GlobalShortcutAction
    let shortcut: GlobalShortcut
    let reason: String

    var errorDescription: String? {
        "Couldn’t register \(action.displayName) (\(shortcut.displayName)): \(reason)"
    }
}

private enum CarbonGlobalShortcutError: Error, LocalizedError {
    case couldNotInstallHandler(OSStatus)
    case shortcutInUse
    case couldNotRegister(OSStatus)

    var errorDescription: String? {
        switch self {
        case .couldNotInstallHandler(let status):
            return "The system shortcut handler could not start (error \(status))."
        case .shortcutInUse:
            return "That shortcut is already in use by Recall or another app."
        case .couldNotRegister(let status):
            return "macOS rejected the shortcut (error \(status))."
        }
    }
}

private final class CarbonShortcutRegistration: GlobalShortcutRegistration {
    let identifier: UInt32
    let reference: EventHotKeyRef

    init(identifier: UInt32, reference: EventHotKeyRef) {
        self.identifier = identifier
        self.reference = reference
    }
}

private final class CarbonShortcutResources: @unchecked Sendable {
    var eventHandlerReference: EventHandlerRef?
    var hotKeyReferences: [UInt32: EventHotKeyRef] = [:]

    deinit {
        for reference in hotKeyReferences.values {
            UnregisterEventHotKey(reference)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
    }
}

@MainActor
final class CarbonGlobalShortcutRegistrar: GlobalShortcutRegistering {
    private var nextIdentifier: UInt32 = 1
    private let resources = CarbonShortcutResources()
    private var callbacks: [UInt32: @MainActor @Sendable () -> Void] = [:]

    func register(
        _ shortcut: GlobalShortcut,
        handler: @escaping @MainActor @Sendable () -> Void
    ) throws -> any GlobalShortcutRegistration {
        try installEventHandlerIfNeeded()

        let identifier = allocateIdentifier()
        let hotKeyID = EventHotKeyID(
            signature: recallGlobalHotKeySignature,
            id: identifier
        )
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.key.carbonKeyCode,
            shortcut.modifiers.carbonFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &reference
        )

        guard status == noErr, let reference else {
            if status == eventHotKeyExistsErr {
                throw CarbonGlobalShortcutError.shortcutInUse
            }
            throw CarbonGlobalShortcutError.couldNotRegister(status)
        }

        callbacks[identifier] = handler
        resources.hotKeyReferences[identifier] = reference
        return CarbonShortcutRegistration(identifier: identifier, reference: reference)
    }

    func unregister(_ registration: any GlobalShortcutRegistration) {
        guard let registration = registration as? CarbonShortcutRegistration else {
            return
        }
        callbacks[registration.identifier] = nil
        resources.hotKeyReferences[registration.identifier] = nil
        UnregisterEventHotKey(registration.reference)
    }

    nonisolated fileprivate func receiveHotKey(identifier: UInt32) {
        Task { @MainActor [weak self] in
            self?.callbacks[identifier]?()
        }
    }

    private func installEventHandlerIfNeeded() throws {
        guard resources.eventHandlerReference == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handlerReference: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            recallGlobalHotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerReference
        )

        guard status == noErr, let handlerReference else {
            throw CarbonGlobalShortcutError.couldNotInstallHandler(status)
        }
        resources.eventHandlerReference = handlerReference
    }

    private func allocateIdentifier() -> UInt32 {
        defer {
            nextIdentifier = nextIdentifier == UInt32.max ? 1 : nextIdentifier + 1
        }
        return nextIdentifier
    }
}

private func recallGlobalHotKeyEventHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    guard hotKeyID.signature == recallGlobalHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }

    let registrar = Unmanaged<CarbonGlobalShortcutRegistrar>
        .fromOpaque(userData)
        .takeUnretainedValue()
    registrar.receiveHotKey(identifier: hotKeyID.id)
    return noErr
}

private extension GlobalShortcutModifiers {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}
