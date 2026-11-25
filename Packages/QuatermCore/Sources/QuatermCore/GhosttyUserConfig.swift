import Foundation

/// The user's own Ghostty config files, read as a base under Quaterm's settings.
public enum GhosttyUserConfig {
    /// `$XDG_CONFIG_HOME/ghostty`, or `~/.config/ghostty`.
    static func xdgDirectory(home: URL, environment: [String: String]) -> URL {
        let xdg =
            environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appending(path: ".config")
        return xdg.appending(path: "ghostty")
    }

    /// Where Ghostty looks for the user's own themes.
    public static func themesDirectory(home: URL, environment: [String: String]) -> URL {
        xdgDirectory(home: home, environment: environment).appending(path: "themes")
    }

    /// The theme a `theme` value picks for one appearance: `light:A,dark:B`, or one name for both.
    public static func themeName(_ value: String, dark: Bool) -> String {
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let prefix = dark ? "dark:" : "light:"
        let picked = parts.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) } ?? value
        let name = picked.trimmingCharacters(in: .whitespaces)
        return name.count >= 2 && name.hasPrefix("\"") && name.hasSuffix("\"") ? String(name.dropFirst().dropLast()) : name
    }

    /// Files Ghostty reads on macOS, in load order: a later file overrides an earlier one.
    public static func candidateURLs(home: URL, environment: [String: String]) -> [URL] {
        let dirs = [
            xdgDirectory(home: home, environment: environment),
            home.appending(path: "Library/Application Support/com.mitchellh.ghostty"),
        ]
        return dirs.flatMap { [$0.appending(path: "config.ghostty"), $0.appending(path: "config")] }
    }

    /// File the "open Ghostty config" menu opens: the last one that exists (it wins), else the
    /// plain XDG one, which the caller creates.
    public static func editableURL(existing: [URL], candidates: [URL]) -> URL {
        existing.last ?? candidates[1]
    }

    public struct Entry: Equatable, Sendable {
        public let key: String
        public let value: String
        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    public struct Loaded: Equatable, Sendable {
        public var entries: [Entry] = []
        /// Files that could not be used. Any problem means the whole user config is left out.
        public var problems: [String] = []
    }

    /// Keys whose value is a file path. Ghostty resolves a relative one against the config file,
    /// but Quaterm hands the lines to Ghostty in a file of its own, so they are made absolute here.
    static let pathKeys: Set<String> = ["custom-shader", "background-image"]

    /// Reads `files` and the files they include, in Ghostty's order: every listed file first,
    /// then the includes, each include's own includes after those. libghostty does not follow
    /// `config-file` itself, so the includes are spliced in here. `read` returns nil for a file
    /// that does not exist.
    public static func load(files: [URL], read: (URL) throws -> String?) -> Loaded {
        var loaded = Loaded()
        var queue: [(url: URL, required: Bool)] = files.map { ($0, false) }
        var seen: Set<String> = []
        var next = 0
        while next < queue.count {
            let (url, required) = queue[next]
            next += 1
            let path = url.standardizedFileURL.path
            // A file named twice (a shared include, or a cycle) is read once, as Ghostty does.
            // Only files that were read count, so a required include of an absent file still
            // reports it even when the file is also one of the optional candidates.
            guard !seen.contains(path) else { continue }
            let contents: String?
            do {
                contents = try read(url)
            } catch {
                loaded.problems.append(Messages.ghosttyConfigUnreadable(path))
                continue
            }
            guard let contents else {
                if required { loaded.problems.append(Messages.ghosttyConfigMissing(path)) }
                continue
            }
            seen.insert(path)
            let directory = url.deletingLastPathComponent()
            var includes: [(url: URL, required: Bool)] = []
            for entry in entries(contents: contents) {
                switch entry.key {
                case "config-file":
                    if let include = filePath(entry.value, directory: directory) {
                        includes.append(include)
                    } else {
                        // `config-file =` clears the includes named so far, as in Ghostty: in this
                        // file and those still waiting from earlier files, not the listed files.
                        includes.removeAll()
                        queue.removeSubrange(max(next, files.count)...)
                    }
                case let key where pathKeys.contains(key):
                    let file = filePath(entry.value, directory: directory)
                    let value = file.map { ($0.required ? "" : "?") + $0.url.path } ?? entry.value
                    loaded.entries.append(Entry(key: key, value: value))
                default:
                    loaded.entries.append(entry)
                }
            }
            queue += includes
        }
        return loaded
    }

    /// 1-based line numbers of `file` that Ghostty diagnostics such as
    /// `/tmp/x.conf:29:keybind: invalid format` point at.
    public static func diagnosedLines(_ diagnostics: [String], file: String) -> Set<Int> {
        Set(
            diagnostics.compactMap { message in
                guard message.hasPrefix(file + ":") else { return nil }
                return Int(message.dropFirst(file.count + 1).prefix { $0.isNumber })
            })
    }

    /// `key = value` entries of one file. Comments and blank lines are dropped. A bare `key`
    /// (Ghostty's way to switch a flag on) becomes `key = true`, because an empty value would
    /// reset it instead.
    public static func entries(contents: String) -> [Entry] {
        contents.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            guard let eq = line.firstIndex(of: "=") else { return Entry(key: line, value: "true") }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            return key.isEmpty ? nil : Entry(key: key, value: value)
        }
    }

    /// `?` marks an optional file; quotes are allowed around the path. A relative path is
    /// relative to the including file. nil for an empty value, Ghostty's "clear the list".
    static func filePath(_ value: String, directory: URL) -> (url: URL, required: Bool)? {
        var path = value
        let optional = path.hasPrefix("?")
        if optional { path.removeFirst() }
        if path.count >= 2, path.hasPrefix("\""), path.hasSuffix("\"") {
            path = String(path.dropFirst().dropLast())
        }
        guard !path.isEmpty else { return nil }
        let url =
            if path.hasPrefix("~/") {
                FileManager.default.homeDirectoryForCurrentUser.appending(path: String(path.dropFirst(2)))
            } else if path.hasPrefix("/") {
                URL(fileURLWithPath: path)
            } else {
                directory.appending(path: path)
            }
        return (url.standardizedFileURL, !optional)
    }
}
