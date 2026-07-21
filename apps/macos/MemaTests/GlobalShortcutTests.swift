import Foundation
import XCTest

@testable import Mema

@MainActor
final class GlobalShortcutTests: XCTestCase {
    func testDefaultsUseRequestedThreeModifierShortcuts() {
        let configuration = GlobalShortcutConfiguration.default

        XCTAssertEqual(configuration.selection.key, .s)
        XCTAssertEqual(configuration.selection.modifiers, [.option, .shift, .command])
        XCTAssertEqual(configuration.selection.displayName, "⌥⇧⌘S")
        XCTAssertTrue(configuration.selection.isEnabled)
        XCTAssertEqual(configuration.clipboard.key, .c)
        XCTAssertEqual(configuration.clipboard.modifiers, [.option, .shift, .command])
        XCTAssertEqual(configuration.clipboard.displayName, "⌥⇧⌘C")
        XCTAssertTrue(configuration.clipboard.isEnabled)
        XCTAssertEqual(configuration.screenshot.key, .digit4)
        XCTAssertEqual(configuration.screenshot.modifiers, [.option, .shift, .command])
        XCTAssertEqual(configuration.screenshot.displayName, "⌥⇧⌘4")
        XCTAssertTrue(configuration.screenshot.isEnabled)
    }

    func testValidationRequiresAtLeastTwoModifiers() {
        var configuration = GlobalShortcutConfiguration.default
        configuration.clipboard.modifiers = [.command]

        XCTAssertThrowsError(try configuration.validate()) { error in
            XCTAssertEqual(
                error as? GlobalShortcutValidationError,
                .notEnoughModifiers(action: .clipboard)
            )
        }
    }

    func testValidationAllowsDisabledActionToReuseAnActiveShortcut() {
        var configuration = GlobalShortcutConfiguration.default
        configuration.screenshot = configuration.clipboard
        configuration.screenshot.isEnabled = false

        XCTAssertNoThrow(try configuration.validate())
    }

    func testValidationRejectsAnyTwoEnabledActionsWithTheSameShortcut() {
        var configuration = GlobalShortcutConfiguration.default
        configuration.selection = configuration.clipboard

        XCTAssertThrowsError(try configuration.validate()) { error in
            XCTAssertEqual(
                error as? GlobalShortcutValidationError,
                .duplicateShortcut
            )
        }
    }

    func testValidationIgnoresModifiersForDisabledActions() {
        var configuration = GlobalShortcutConfiguration.default
        configuration.clipboard.isEnabled = false
        configuration.clipboard.modifiers = []

        XCTAssertNoThrow(try configuration.validate())
    }

    func testSuccessfulApplyRegistersBeforePersistingConfiguration() throws {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        let center = GlobalShortcutCenter(
            userDefaults: harness.userDefaults,
            registrar: harness.registrar
        )
        let initialConfiguration = center.configuration
        var persistedConfigurationsDuringRegistration: [GlobalShortcutConfiguration?] = []
        harness.registrar.onRegister = {
            persistedConfigurationsDuringRegistration.append(
                Self.persistedConfiguration(in: harness.userDefaults)
            )
        }
        let proposedConfiguration = customConfiguration()

        XCTAssertTrue(center.apply(proposedConfiguration))

        XCTAssertEqual(center.configuration, proposedConfiguration)
        XCTAssertEqual(
            Set(harness.registrar.activeShortcuts),
            Set(GlobalShortcutAction.allCases.map { proposedConfiguration[$0] })
        )
        XCTAssertEqual(
            try XCTUnwrap(Self.persistedConfiguration(in: harness.userDefaults)),
            proposedConfiguration
        )
        XCTAssertEqual(persistedConfigurationsDuringRegistration.count, 3)
        XCTAssertTrue(
            persistedConfigurationsDuringRegistration.allSatisfy {
                $0 == nil || $0 == initialConfiguration
            }
        )
        XCTAssertNil(center.errorMessage)
    }

    func testRegistrationFailureRollsBackRegistrationsAndPersistence() throws {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        let center = GlobalShortcutCenter(
            userDefaults: harness.userDefaults,
            registrar: harness.registrar
        )
        let stableConfiguration = customConfiguration()
        XCTAssertTrue(center.apply(stableConfiguration))

        var rejectedConfiguration = stableConfiguration
        rejectedConfiguration.clipboard = GlobalShortcut(
            key: .a,
            modifiers: [.command, .shift]
        )
        rejectedConfiguration.screenshot = GlobalShortcut(
            key: .x,
            modifiers: [.control, .option]
        )
        harness.registrar.rejectedShortcut = rejectedConfiguration.screenshot

        XCTAssertFalse(center.apply(rejectedConfiguration))

        XCTAssertEqual(center.configuration, stableConfiguration)
        XCTAssertEqual(
            Set(harness.registrar.activeShortcuts),
            Set(GlobalShortcutAction.allCases.map { stableConfiguration[$0] })
        )
        XCTAssertEqual(
            try XCTUnwrap(Self.persistedConfiguration(in: harness.userDefaults)),
            stableConfiguration
        )
        XCTAssertTrue(center.errorMessage?.contains("already in use") == true)
        XCTAssertTrue(center.errorMessage?.contains("previous shortcuts were restored") == true)
        XCTAssertNil(center.registrationErrorMessage)
    }

    func testRegistrationFailureCleansUpPartialInitialRegistration() {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        harness.registrar.rejectedShortcut = GlobalShortcutConfiguration.default.screenshot

        let center = GlobalShortcutCenter(
            userDefaults: harness.userDefaults,
            registrar: harness.registrar
        )

        XCTAssertTrue(harness.registrar.activeShortcuts.isEmpty)
        XCTAssertTrue(center.activeActions.isEmpty)
        XCTAssertTrue(center.errorMessage?.contains("already in use") == true)
        XCTAssertTrue(center.registrationErrorMessage?.contains("already in use") == true)
    }

    func testDisablingOneActionUnregistersItAndPersistsTheChoice() throws {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        let center = GlobalShortcutCenter(
            userDefaults: harness.userDefaults,
            registrar: harness.registrar
        )

        XCTAssertTrue(center.setEnabled(false, for: .clipboard))

        XCTAssertFalse(center.configuration.clipboard.isEnabled)
        XCTAssertEqual(center.activeActions, [.selection, .screenshot])
        XCTAssertEqual(
            Set(harness.registrar.activeShortcuts),
            Set([
                GlobalShortcutConfiguration.default.selection,
                GlobalShortcutConfiguration.default.screenshot,
            ])
        )
        XCTAssertFalse(
            try XCTUnwrap(Self.persistedConfiguration(in: harness.userDefaults))
                .clipboard.isEnabled
        )
    }

    func testRestoreDefaultsReplacesCustomConfiguration() {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        let center = GlobalShortcutCenter(
            userDefaults: harness.userDefaults,
            registrar: harness.registrar
        )
        XCTAssertTrue(center.apply(customConfiguration()))

        XCTAssertTrue(center.restoreDefaults())

        XCTAssertEqual(center.configuration, .default)
        XCTAssertEqual(
            Set(harness.registrar.activeShortcuts),
            Set([
                GlobalShortcutConfiguration.default.selection,
                GlobalShortcutConfiguration.default.clipboard,
                GlobalShortcutConfiguration.default.screenshot,
            ])
        )
    }

    func testPersistedConfigurationLoadsAndRegistersAtStartup() throws {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        let storedConfiguration = customConfiguration()
        harness.userDefaults.set(
            try JSONEncoder().encode(storedConfiguration),
            forKey: GlobalShortcutCenter.userDefaultsKey
        )

        let center = GlobalShortcutCenter(
            userDefaults: harness.userDefaults,
            registrar: harness.registrar
        )

        XCTAssertEqual(center.configuration, storedConfiguration)
        XCTAssertEqual(
            Set(harness.registrar.activeShortcuts),
            Set(GlobalShortcutAction.allCases.map { storedConfiguration[$0] })
        )
    }

    func testLegacyTwoActionConfigurationPreservesValuesAndAddsSelection() throws {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        let legacyClipboard = GlobalShortcut(
            key: .k,
            modifiers: [.control, .command],
            isEnabled: false
        )
        let legacyScreenshot = GlobalShortcut(
            key: .digit7,
            modifiers: [.option, .shift]
        )
        harness.userDefaults.set(
            try JSONSerialization.data(withJSONObject: [
                "clipboard": encodedJSONObject(for: legacyClipboard),
                "screenshot": encodedJSONObject(for: legacyScreenshot),
            ]),
            forKey: GlobalShortcutCenter.userDefaultsKey
        )

        let center = GlobalShortcutCenter(
            userDefaults: harness.userDefaults,
            registrar: harness.registrar
        )

        XCTAssertEqual(center.configuration.clipboard, legacyClipboard)
        XCTAssertEqual(center.configuration.screenshot, legacyScreenshot)
        XCTAssertEqual(
            center.configuration.selection,
            GlobalShortcutConfiguration.defaultSelection
        )
        XCTAssertEqual(center.activeActions, [.selection, .screenshot])
        XCTAssertNil(center.errorMessage)
        XCTAssertNotNil(
            try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: try XCTUnwrap(
                        harness.userDefaults.data(
                            forKey: GlobalShortcutCenter.userDefaultsKey
                        )
                    )
                ) as? [String: Any]
            )["selection"]
        )
    }

    func testLegacySelectionShortcutConflictDisablesOnlyMigratedAction() throws {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        let conflictingScreenshot = GlobalShortcutConfiguration.default.selection
        harness.userDefaults.set(
            try JSONSerialization.data(withJSONObject: [
                "clipboard": encodedJSONObject(
                    for: GlobalShortcutConfiguration.default.clipboard
                ),
                "screenshot": encodedJSONObject(for: conflictingScreenshot),
            ]),
            forKey: GlobalShortcutCenter.userDefaultsKey
        )

        let center = GlobalShortcutCenter(
            userDefaults: harness.userDefaults,
            registrar: harness.registrar
        )

        XCTAssertEqual(center.configuration.screenshot, conflictingScreenshot)
        XCTAssertFalse(center.configuration.selection.isEnabled)
        XCTAssertEqual(center.configuration.selection.key, .s)
        XCTAssertEqual(center.activeActions, [.clipboard, .screenshot])
        XCTAssertNil(center.errorMessage)
    }

    func testLegacyExternalSelectionConflictKeepsExistingShortcutsActive() throws {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        harness.userDefaults.set(
            try JSONSerialization.data(withJSONObject: [
                "clipboard": encodedJSONObject(
                    for: GlobalShortcutConfiguration.default.clipboard
                ),
                "screenshot": encodedJSONObject(
                    for: GlobalShortcutConfiguration.default.screenshot
                ),
            ]),
            forKey: GlobalShortcutCenter.userDefaultsKey
        )
        harness.registrar.rejectedShortcut = GlobalShortcutConfiguration.default.selection

        let center = GlobalShortcutCenter(
            userDefaults: harness.userDefaults,
            registrar: harness.registrar
        )

        XCTAssertFalse(center.configuration.selection.isEnabled)
        XCTAssertEqual(center.activeActions, [.clipboard, .screenshot])
        XCTAssertEqual(
            Set(harness.registrar.activeShortcuts),
            Set([
                GlobalShortcutConfiguration.default.clipboard,
                GlobalShortcutConfiguration.default.screenshot,
            ])
        )
        XCTAssertTrue(center.errorMessage?.contains("existing shortcuts active") == true)
        XCTAssertNil(center.registrationErrorMessage)
        XCTAssertFalse(
            try XCTUnwrap(Self.persistedConfiguration(in: harness.userDefaults))
                .selection.isEnabled
        )
    }

    func testLegacyExistingActionConflictDoesNotMislabelOrDisableSelection() throws {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        harness.userDefaults.set(
            try JSONSerialization.data(withJSONObject: [
                "clipboard": encodedJSONObject(
                    for: GlobalShortcutConfiguration.default.clipboard
                ),
                "screenshot": encodedJSONObject(
                    for: GlobalShortcutConfiguration.default.screenshot
                ),
            ]),
            forKey: GlobalShortcutCenter.userDefaultsKey
        )
        harness.registrar.rejectedShortcut = GlobalShortcutConfiguration.default.clipboard

        let center = GlobalShortcutCenter(
            userDefaults: harness.userDefaults,
            registrar: harness.registrar
        )

        XCTAssertTrue(center.configuration.selection.isEnabled)
        XCTAssertTrue(center.activeActions.isEmpty)
        XCTAssertFalse(center.errorMessage?.contains("new Selection") == true)
        XCTAssertNotNil(center.registrationErrorMessage)
    }

    func testInvalidPersistedConfigurationIsRemovedAfterFallingBackToDefaults() {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        harness.userDefaults.set(
            Data("not valid JSON".utf8),
            forKey: GlobalShortcutCenter.userDefaultsKey
        )

        let center = GlobalShortcutCenter(
            userDefaults: harness.userDefaults,
            registrar: harness.registrar
        )

        XCTAssertEqual(center.configuration, .default)
        XCTAssertNil(harness.userDefaults.data(forKey: GlobalShortcutCenter.userDefaultsKey))
        XCTAssertNotNil(center.errorMessage)
        XCTAssertNil(center.registrationErrorMessage)
        XCTAssertEqual(
            Set(harness.registrar.activeShortcuts),
            Set([
                GlobalShortcutConfiguration.default.selection,
                GlobalShortcutConfiguration.default.clipboard,
                GlobalShortcutConfiguration.default.screenshot,
            ])
        )
    }

    func testValidationFailureDoesNotReportAnActivationFailure() {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        let center = GlobalShortcutCenter(
            userDefaults: harness.userDefaults,
            registrar: harness.registrar
        )
        var invalidConfiguration = center.configuration
        invalidConfiguration.clipboard.modifiers = [.command]

        XCTAssertFalse(center.apply(invalidConfiguration))

        XCTAssertNotNil(center.errorMessage)
        XCTAssertNil(center.registrationErrorMessage)
        XCTAssertEqual(center.activeActions, Set(GlobalShortcutAction.allCases))
    }

    func testRegistrarCallbackDeliversInjectedActionOnMainActor() {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        let recorder = ShortcutActionRecorder()
        let center = GlobalShortcutCenter(
            userDefaults: harness.userDefaults,
            registrar: harness.registrar
        ) { action in
            MainActor.preconditionIsolated()
            recorder.actions.append(action)
        }

        harness.registrar.fire(GlobalShortcutConfiguration.default.clipboard)
        harness.registrar.fire(GlobalShortcutConfiguration.default.screenshot)
        harness.registrar.fire(GlobalShortcutConfiguration.default.selection)

        XCTAssertEqual(recorder.actions, [.clipboard, .screenshot, .selection])
        withExtendedLifetime(center) {}
    }

    private func customConfiguration() -> GlobalShortcutConfiguration {
        GlobalShortcutConfiguration(
            clipboard: GlobalShortcut(
                key: .k,
                modifiers: [.command, .option]
            ),
            screenshot: GlobalShortcut(
                key: .s,
                modifiers: [.control, .shift]
            )
        )
    }

    private func makeHarness() -> ShortcutTestHarness {
        let suiteName = "GlobalShortcutTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return ShortcutTestHarness(
            suiteName: suiteName,
            userDefaults: userDefaults,
            registrar: FakeGlobalShortcutRegistrar()
        )
    }

    private static func persistedConfiguration(
        in userDefaults: UserDefaults
    ) -> GlobalShortcutConfiguration? {
        guard let data = userDefaults.data(forKey: GlobalShortcutCenter.userDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(GlobalShortcutConfiguration.self, from: data)
    }

    private func encodedJSONObject(for shortcut: GlobalShortcut) throws -> Any {
        let data = try JSONEncoder().encode(shortcut)
        return try JSONSerialization.jsonObject(with: data)
    }
}

@MainActor
private final class ShortcutActionRecorder {
    var actions: [GlobalShortcutAction] = []
}

@MainActor
private struct ShortcutTestHarness {
    let suiteName: String
    let userDefaults: UserDefaults
    let registrar: FakeGlobalShortcutRegistrar

    func cleanUp() {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class FakeGlobalShortcutRegistrar: GlobalShortcutRegistering {
    private final class Registration: GlobalShortcutRegistration {
        let id = UUID()
        let shortcut: GlobalShortcut

        init(shortcut: GlobalShortcut) {
            self.shortcut = shortcut
        }
    }

    private struct ActiveRegistration {
        let registration: Registration
        let handler: @MainActor @Sendable () -> Void
    }

    var rejectedShortcut: GlobalShortcut?
    var onRegister: (() -> Void)?
    private var active: [UUID: ActiveRegistration] = [:]

    var activeShortcuts: [GlobalShortcut] {
        active.values.map(\.registration.shortcut)
    }

    func register(
        _ shortcut: GlobalShortcut,
        handler: @escaping @MainActor @Sendable () -> Void
    ) throws -> any GlobalShortcutRegistration {
        onRegister?()
        if shortcut == rejectedShortcut {
            throw FakeGlobalShortcutRegistrationError.conflict
        }

        let registration = Registration(shortcut: shortcut)
        active[registration.id] = ActiveRegistration(
            registration: registration,
            handler: handler
        )
        return registration
    }

    func unregister(_ registration: any GlobalShortcutRegistration) {
        guard let registration = registration as? Registration else { return }
        active[registration.id] = nil
    }

    func fire(_ shortcut: GlobalShortcut) {
        active.values
            .first(where: { $0.registration.shortcut == shortcut })?
            .handler()
    }
}

private enum FakeGlobalShortcutRegistrationError: Error, LocalizedError {
    case conflict

    var errorDescription: String? {
        "That shortcut is already in use."
    }
}
