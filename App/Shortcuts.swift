import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// The only shortcut registered system-wide.
    nonisolated(unsafe) static let toggleTerminal = Self("toggleTerminal", default: .init(.backtick, modifiers: [.control]))

    // Matched only while the terminal panel is key, so other apps keep these keys.
    nonisolated(unsafe) static let togglePin = Self("togglePin", default: .init(.p, modifiers: [.command, .shift]))
    nonisolated(unsafe) static let newTab = Self("newTab", default: .init(.t, modifiers: [.command]))
    nonisolated(unsafe) static let closeTab = Self("closeTab", default: .init(.w, modifiers: [.command]))
    nonisolated(unsafe) static let growWindow = Self("growWindow", default: .init(.equal, modifiers: [.command, .option]))
    nonisolated(unsafe) static let shrinkWindow = Self("shrinkWindow", default: .init(.minus, modifiers: [.command, .option]))
}

extension KeyboardShortcuts.Shortcut {
    nonisolated(unsafe) static let quit = Self(.q, modifiers: [.command])
}

/// Panel-local actions, in the order the matcher checks them.
enum LocalAction: CaseIterable {
    case togglePin, newTab, closeTab, growWindow, shrinkWindow

    var name: KeyboardShortcuts.Name {
        switch self {
        case .togglePin: .togglePin
        case .newTab: .newTab
        case .closeTab: .closeTab
        case .growWindow: .growWindow
        case .shrinkWindow: .shrinkWindow
        }
    }

    static func matching(_ event: NSEvent) -> LocalAction? {
        guard let pressed = KeyboardShortcuts.Shortcut(event: event) else { return nil }
        return allCases.first { KeyboardShortcuts.getShortcut(for: $0.name) == pressed }
    }
}

extension KeyboardShortcuts {
    /// KeyboardShortcuts registers every named shortcut as a system-wide hot key: once when the
    /// name is first created with a default, and again each time the recorder changes it.
    /// The panel-local ones must not be, or Cmd+T and friends stop working in every other app.
    /// A local shortcut equal to the toggle shortcut stays registered, because unregistering
    /// works by key combination and would take the toggle down with it.
    static func unregisterLocalShortcuts() {
        let toggle = getShortcut(for: .toggleTerminal)
        for action in LocalAction.allCases where getShortcut(for: action.name) != toggle {
            disable(action.name)
        }
    }
}
