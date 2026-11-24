/// Ghostty config entries derived from the user's settings.
public enum GhosttyConfig {
    public static func entries(scrollbackLines: Int, copyOnSelect: Bool) -> [(key: String, value: String)] {
        let lines = clamp(scrollbackLines, Constants.scrollbackLinesRange)
        return [
            ("scrollback-limit-lines", String(lines)),
            ("scrollback-limit-bytes", String(lines * Constants.scrollbackBytesPerLine)),
            // "clipboard" copies to the system clipboard; Ghostty's macOS default only fills a private pasteboard.
            ("copy-on-select", copyOnSelect ? "clipboard" : "none"),
            // Quaterm handles tab/window keys itself; keep Ghostty from also acting on them.
            ("keybind", "super+t=unbind"),
            ("keybind", "super+w=unbind"),
            ("keybind", "super+q=unbind"),
        ]
    }
}
