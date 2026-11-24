import Foundation

/// Values that never change at runtime. Defaults for user settings live here too.
public enum Constants {
    public static let defaultHeightRatio = 0.4
    public static let heightRatioRange = 0.2...1.0
    public static let resizeStep = 0.05

    public static let defaultAnimationDuration = 0.2
    public static let animationDurationRange = 0.0...1.0

    public static let defaultScrollbackLines = 10_000
    public static let scrollbackLinesRange = 100...1_000_000
    /// Ghostty stops at whichever scrollback limit (bytes or lines) it hits first,
    /// so the byte limit is raised in step with the line limit.
    // ponytail: fixed per-line budget; measure real usage if very wide terminals hit the byte cap first
    public static let scrollbackBytesPerLine = 16_384

    public static let defaultNotifyMinSeconds = 10
    public static let notifyMinSecondsRange = 0...3600

    public static let tabBarHeight = 28.0

    /// Background opacity while "translucent" is on.
    public static let defaultTranslucentOpacity = 0.8
    public static let translucentOpacityRange = 0.2...0.95
}

public enum SlideEdge: String, CaseIterable, Sendable {
    case top
    case bottom
}

public enum DisplayMode: String, CaseIterable, Sendable {
    case main
    case active
    case specific
}

/// Where to show the window when the chosen display is gone.
public enum FallbackDisplay: String, CaseIterable, Sendable {
    case main
    case active
}

public enum NotifyResult: String, CaseIterable, Sendable {
    case always
    case failureOnly
}

/// UserDefaults keys. Shared by the AppKit side and the SwiftUI preferences (`@AppStorage`).
public enum SettingsKey {
    public static let showInDock = "showInDock"
    public static let scrollbackLines = "scrollbackLines"
    public static let slideEdge = "slideEdge"
    public static let animationDuration = "animationDuration"
    public static let fade = "fade"
    public static let copyOnSelect = "copyOnSelect"
    public static let displayMode = "displayMode"
    public static let specificDisplayID = "specificDisplayID"
    public static let fallbackDisplay = "fallbackDisplay"
    public static let heightRatio = "heightRatio"
    public static let notifyMinSeconds = "notifyMinSeconds"
    public static let notifyResult = "notifyResult"
    public static let confirmQuit = "confirmQuit"
    public static let confirmCloseLastTab = "confirmCloseLastTab"
    public static let translucent = "translucent"
    public static let translucentOpacity = "translucentOpacity"
    public static let lastPreferencesPane = "lastPreferencesPane"
}

/// Typed view over UserDefaults. Missing values fall back to the defaults in `Constants`.
public struct AppSettings {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            SettingsKey.showInDock: true,
            SettingsKey.scrollbackLines: Constants.defaultScrollbackLines,
            SettingsKey.slideEdge: SlideEdge.top.rawValue,
            SettingsKey.animationDuration: Constants.defaultAnimationDuration,
            SettingsKey.fade: false,
            SettingsKey.copyOnSelect: false,
            SettingsKey.displayMode: DisplayMode.active.rawValue,
            SettingsKey.heightRatio: Constants.defaultHeightRatio,
            SettingsKey.notifyMinSeconds: Constants.defaultNotifyMinSeconds,
            SettingsKey.notifyResult: NotifyResult.always.rawValue,
            SettingsKey.confirmQuit: true,
            SettingsKey.confirmCloseLastTab: true,
            SettingsKey.translucent: false,
            SettingsKey.translucentOpacity: Constants.defaultTranslucentOpacity,
        ])
    }

    public var showInDock: Bool { defaults.bool(forKey: SettingsKey.showInDock) }
    public var fade: Bool { defaults.bool(forKey: SettingsKey.fade) }
    public var copyOnSelect: Bool { defaults.bool(forKey: SettingsKey.copyOnSelect) }

    public var confirmQuit: Bool {
        get { defaults.bool(forKey: SettingsKey.confirmQuit) }
        nonmutating set { defaults.set(newValue, forKey: SettingsKey.confirmQuit) }
    }

    public var confirmCloseLastTab: Bool {
        get { defaults.bool(forKey: SettingsKey.confirmCloseLastTab) }
        nonmutating set { defaults.set(newValue, forKey: SettingsKey.confirmCloseLastTab) }
    }

    public var translucent: Bool {
        get { defaults.bool(forKey: SettingsKey.translucent) }
        nonmutating set { defaults.set(newValue, forKey: SettingsKey.translucent) }
    }

    /// Opacity Ghostty draws the background with: the slider value while translucent, else opaque.
    public var backgroundOpacity: Double {
        translucent ? clamp(defaults.double(forKey: SettingsKey.translucentOpacity), Constants.translucentOpacityRange) : 1
    }

    public var scrollbackLines: Int {
        clamp(defaults.integer(forKey: SettingsKey.scrollbackLines), Constants.scrollbackLinesRange)
    }

    public var animationDuration: Double {
        clamp(defaults.double(forKey: SettingsKey.animationDuration), Constants.animationDurationRange)
    }

    public var notifyMinSeconds: Int {
        clamp(defaults.integer(forKey: SettingsKey.notifyMinSeconds), Constants.notifyMinSecondsRange)
    }

    public var heightRatio: Double {
        get { clamp(defaults.double(forKey: SettingsKey.heightRatio), Constants.heightRatioRange) }
        nonmutating set { defaults.set(clamp(newValue, Constants.heightRatioRange), forKey: SettingsKey.heightRatio) }
    }

    public var slideEdge: SlideEdge { value(SettingsKey.slideEdge) ?? .top }
    public var displayMode: DisplayMode { value(SettingsKey.displayMode) ?? .active }
    public var notifyResult: NotifyResult { value(SettingsKey.notifyResult) ?? .always }

    /// The preferences picker stores "" for "not selected"; that is the same as no value.
    public var specificDisplayID: String? {
        defaults.string(forKey: SettingsKey.specificDisplayID).flatMap { $0.isEmpty ? nil : $0 }
    }

    public var fallbackDisplay: FallbackDisplay? {
        get { value(SettingsKey.fallbackDisplay) }
        nonmutating set { defaults.set(newValue?.rawValue, forKey: SettingsKey.fallbackDisplay) }
    }

    private func value<T: RawRepresentable>(_ key: String) -> T? where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:))
    }
}

func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
    min(max(value, range.lowerBound), range.upperBound)
}
