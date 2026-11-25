/// Which tab the next / previous tab keys select.
public enum TabNavigation {
    /// Index `offset` tabs away from `current`, wrapping around both ends. nil when there are no tabs.
    public static func cycledIndex(from current: Int, by offset: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return ((current + offset) % count + count) % count
    }
}
