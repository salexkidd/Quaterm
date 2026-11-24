/// Ghostty config entries derived from the user's settings.
public enum GhosttyConfig {
    public static func entries(
        scrollbackLines: Int,
        copyOnSelect: Bool,
        backgroundOpacity: Double,
        fontFamily: String,
        fontSize: Double
    ) -> [(key: String, value: String)] {
        let lines = clamp(scrollbackLines, Constants.scrollbackLinesRange)
        // font-family repeats as a fallback list; "" clears it so the choice replaces the default.
        let font: [(key: String, value: String)] = fontFamily.isEmpty ? [] : [("font-family", ""), ("font-family", fontFamily)]
        return font + [
            ("font-size", String(clamp(fontSize, Constants.fontSizeRange))),
            ("scrollback-limit-lines", String(lines)),
            ("scrollback-limit-bytes", String(lines * Constants.scrollbackBytesPerLine)),
            // "clipboard" copies to the system clipboard; Ghostty's macOS default only fills a private pasteboard.
            ("copy-on-select", copyOnSelect ? "clipboard" : "none"),
            ("background-opacity", String(backgroundOpacity)),
            // Quaterm handles tab/window keys itself; keep Ghostty from also acting on them.
            ("keybind", "super+t=unbind"),
            ("keybind", "super+w=unbind"),
            ("keybind", "super+q=unbind"),
        ]
    }
}
