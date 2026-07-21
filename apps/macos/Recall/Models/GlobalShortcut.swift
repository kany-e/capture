import Foundation

enum GlobalShortcutAction: String, CaseIterable, Codable, Hashable, Sendable {
    case clipboard
    case screenshot

    var displayName: String {
        switch self {
        case .clipboard:
            return "Clipboard capture"
        case .screenshot:
            return "Screenshot capture"
        }
    }
}

enum GlobalShortcutKey: String, CaseIterable, Codable, Hashable, Sendable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case e = "E"
    case f = "F"
    case g = "G"
    case h = "H"
    case i = "I"
    case j = "J"
    case k = "K"
    case l = "L"
    case m = "M"
    case n = "N"
    case o = "O"
    case p = "P"
    case q = "Q"
    case r = "R"
    case s = "S"
    case t = "T"
    case u = "U"
    case v = "V"
    case w = "W"
    case x = "X"
    case y = "Y"
    case z = "Z"
    case digit0 = "0"
    case digit1 = "1"
    case digit2 = "2"
    case digit3 = "3"
    case digit4 = "4"
    case digit5 = "5"
    case digit6 = "6"
    case digit7 = "7"
    case digit8 = "8"
    case digit9 = "9"

    var displayName: String { rawValue }

    // ANSI virtual key codes are physical-key identifiers, so shortcuts keep
    // working independently of the user's current keyboard layout.
    var carbonKeyCode: UInt32 {
        switch self {
        case .a: return 0
        case .b: return 11
        case .c: return 8
        case .d: return 2
        case .e: return 14
        case .f: return 3
        case .g: return 5
        case .h: return 4
        case .i: return 34
        case .j: return 38
        case .k: return 40
        case .l: return 37
        case .m: return 46
        case .n: return 45
        case .o: return 31
        case .p: return 35
        case .q: return 12
        case .r: return 15
        case .s: return 1
        case .t: return 17
        case .u: return 32
        case .v: return 9
        case .w: return 13
        case .x: return 7
        case .y: return 16
        case .z: return 6
        case .digit0: return 29
        case .digit1: return 18
        case .digit2: return 19
        case .digit3: return 20
        case .digit4: return 21
        case .digit5: return 23
        case .digit6: return 22
        case .digit7: return 26
        case .digit8: return 28
        case .digit9: return 25
        }
    }
}

struct GlobalShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    private static let supportedRawValue: UInt8 = 0b1111

    let rawValue: UInt8

    static let command = GlobalShortcutModifiers(rawValue: 1 << 0)
    static let option = GlobalShortcutModifiers(rawValue: 1 << 1)
    static let control = GlobalShortcutModifiers(rawValue: 1 << 2)
    static let shift = GlobalShortcutModifiers(rawValue: 1 << 3)

    static let supported: GlobalShortcutModifiers = [
        .command,
        .option,
        .control,
        .shift,
    ]

    var count: Int {
        Int(rawValue.nonzeroBitCount)
    }

    var displayName: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    init(rawValue: UInt8) {
        self.rawValue = rawValue & Self.supportedRawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decodedRawValue = try container.decode(UInt8.self)
        guard decodedRawValue & ~Self.supportedRawValue == 0 else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "The shortcut contains unsupported modifier bits."
            )
        }
        self.init(rawValue: decodedRawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct GlobalShortcut: Codable, Equatable, Hashable, Sendable {
    var key: GlobalShortcutKey
    var modifiers: GlobalShortcutModifiers
    var isEnabled: Bool

    init(
        key: GlobalShortcutKey,
        modifiers: GlobalShortcutModifiers,
        isEnabled: Bool = true
    ) {
        self.key = key
        self.modifiers = modifiers
        self.isEnabled = isEnabled
    }

    var displayName: String {
        modifiers.displayName + key.displayName
    }
}

struct GlobalShortcutConfiguration: Codable, Equatable, Sendable {
    var clipboard: GlobalShortcut
    var screenshot: GlobalShortcut

    static let `default` = GlobalShortcutConfiguration(
        clipboard: GlobalShortcut(
            key: .c,
            modifiers: [.option, .shift, .command]
        ),
        screenshot: GlobalShortcut(
            key: .digit4,
            modifiers: [.option, .shift, .command]
        )
    )

    subscript(action: GlobalShortcutAction) -> GlobalShortcut {
        get {
            switch action {
            case .clipboard: return clipboard
            case .screenshot: return screenshot
            }
        }
        set {
            switch action {
            case .clipboard: clipboard = newValue
            case .screenshot: screenshot = newValue
            }
        }
    }

    func validate() throws {
        for action in GlobalShortcutAction.allCases {
            let shortcut = self[action]
            guard shortcut.isEnabled else { continue }
            guard shortcut.modifiers.count >= 2 else {
                throw GlobalShortcutValidationError.notEnoughModifiers(action: action)
            }
        }

        guard !clipboard.isEnabled
                || !screenshot.isEnabled
                || clipboard.key != screenshot.key
                || clipboard.modifiers != screenshot.modifiers else {
            throw GlobalShortcutValidationError.duplicateShortcut
        }
    }
}

enum GlobalShortcutValidationError: Error, Equatable, LocalizedError {
    case notEnoughModifiers(action: GlobalShortcutAction)
    case duplicateShortcut

    var errorDescription: String? {
        switch self {
        case .notEnoughModifiers(let action):
            return "\(action.displayName) needs at least two modifier keys."
        case .duplicateShortcut:
            return "Clipboard and screenshot capture cannot use the same shortcut."
        }
    }
}
