/// A connected display, reduced to what the choice needs.
public struct DisplayInfo: Equatable, Sendable {
    public let id: String
    public let isMain: Bool
    public let containsMouse: Bool

    public init(id: String, isMain: Bool, containsMouse: Bool) {
        self.id = id
        self.isMain = isMain
        self.containsMouse = containsMouse
    }
}

public enum DisplayResolution: Equatable, Sendable {
    case display(String)
    /// The chosen display is gone and no fallback is stored yet: ask the user.
    case needsFallbackChoice
}

public enum DisplayResolver {
    public static func resolve(
        mode: DisplayMode,
        specificID: String?,
        fallback: FallbackDisplay?,
        displays: [DisplayInfo]
    ) -> DisplayResolution? {
        guard let main = displays.first(where: \.isMain) ?? displays.first else { return nil }
        let active = displays.first(where: \.containsMouse) ?? main

        switch mode {
        case .main:
            return .display(main.id)
        case .active:
            return .display(active.id)
        case .specific:
            if let specificID, displays.contains(where: { $0.id == specificID }) {
                return .display(specificID)
            }
            // No display picked yet behaves like "active" without asking.
            guard specificID != nil else { return .display(active.id) }
            switch fallback {
            case .main: return .display(main.id)
            case .active: return .display(active.id)
            case nil: return .needsFallbackChoice
            }
        }
    }
}
