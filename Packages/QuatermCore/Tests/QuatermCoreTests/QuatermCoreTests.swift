import CoreGraphics
import Foundation
import Testing
@testable import QuatermCore

@Suite struct WindowGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 2000, height: 1000)
    // Menu bar 40pt on top, Dock 60pt at the bottom.
    let visible = CGRect(x: 0, y: 60, width: 2000, height: 900)

    @Test func topEdgeSitsUnderMenuBarAtFullWidth() {
        let frame = WindowGeometry.shownFrame(screen: screen, visible: visible, edge: .top, heightRatio: 0.4)
        #expect(frame == CGRect(x: 0, y: 600, width: 2000, height: 360))
    }

    @Test func bottomEdgeSitsAboveDock() {
        let frame = WindowGeometry.shownFrame(screen: screen, visible: visible, edge: .bottom, heightRatio: 0.5)
        #expect(frame == CGRect(x: 0, y: 60, width: 2000, height: 450))
    }

    @Test func hiddenFrameStartsPastThePhysicalScreenEdge() {
        let shown = CGRect(x: 0, y: 600, width: 2000, height: 360)
        // Top: fully above the screen, not just above the menu bar.
        #expect(WindowGeometry.hiddenFrame(shown: shown, screen: screen, edge: .top).minY == 1000)
        // Bottom: fully below the screen, not just below the Dock.
        #expect(WindowGeometry.hiddenFrame(shown: shown, screen: screen, edge: .bottom).maxY == 0)
    }

    @Test func resizeStepsAndClamps() {
        #expect(abs(WindowGeometry.resizedRatio(0.4, steps: 1) - 0.45) < 1e-9)
        #expect(abs(WindowGeometry.resizedRatio(0.4, steps: -1) - 0.35) < 1e-9)
        #expect(WindowGeometry.resizedRatio(0.2, steps: -1) == 0.2)
        #expect(WindowGeometry.resizedRatio(1.0, steps: 1) == 1.0)
    }

    @Test func bottomEdgeSwapsGrowAndShrink() {
        #expect(WindowGeometry.resizeSteps(1, edge: .top) == 1)
        #expect(WindowGeometry.resizeSteps(-1, edge: .top) == -1)
        #expect(WindowGeometry.resizeSteps(1, edge: .bottom) == -1)
        #expect(WindowGeometry.resizeSteps(-1, edge: .bottom) == 1)
    }
}

@Suite struct DisplayResolverTests {
    let displays = [
        DisplayInfo(id: "main", isMain: true, containsMouse: false),
        DisplayInfo(id: "side", isMain: false, containsMouse: true),
    ]

    @Test func mainAndActive() {
        #expect(DisplayResolver.resolve(mode: .main, specificID: nil, fallback: nil, displays: displays) == .display("main"))
        #expect(DisplayResolver.resolve(mode: .active, specificID: nil, fallback: nil, displays: displays) == .display("side"))
    }

    @Test func specificDisplayPresent() {
        #expect(DisplayResolver.resolve(mode: .specific, specificID: "main", fallback: nil, displays: displays) == .display("main"))
    }

    @Test func specificDisplayMissingAsksOnce() {
        #expect(DisplayResolver.resolve(mode: .specific, specificID: "gone", fallback: nil, displays: displays) == .needsFallbackChoice)
        #expect(DisplayResolver.resolve(mode: .specific, specificID: "gone", fallback: .main, displays: displays) == .display("main"))
        #expect(DisplayResolver.resolve(mode: .specific, specificID: "gone", fallback: .active, displays: displays) == .display("side"))
    }

    @Test func noDisplaysYieldsNil() {
        #expect(DisplayResolver.resolve(mode: .main, specificID: nil, fallback: nil, displays: []) == nil)
    }
}

@Suite struct CommandNotificationTests {
    let eleven: UInt64 = 11_000_000_000

    @Test func onlyWhenHiddenAndLongEnough() {
        #expect(CommandNotification.shouldNotify(windowVisible: false, exitCode: 0, durationNanos: eleven, minSeconds: 10, result: .always))
        #expect(!CommandNotification.shouldNotify(windowVisible: true, exitCode: 0, durationNanos: eleven, minSeconds: 10, result: .always))
        #expect(
            !CommandNotification.shouldNotify(
                windowVisible: false, exitCode: 0, durationNanos: 9_000_000_000, minSeconds: 10, result: .always))
    }

    @Test func failureOnly() {
        #expect(
            CommandNotification.shouldNotify(windowVisible: false, exitCode: 1, durationNanos: eleven, minSeconds: 10, result: .failureOnly)
        )
        #expect(
            !CommandNotification.shouldNotify(
                windowVisible: false, exitCode: 0, durationNanos: eleven, minSeconds: 10, result: .failureOnly))
        #expect(
            !CommandNotification.shouldNotify(
                windowVisible: false, exitCode: nil, durationNanos: eleven, minSeconds: 10, result: .failureOnly))
    }

    @Test func body() {
        #expect(CommandNotification.body(exitCode: 0, durationNanos: eleven) == "成功 (11 秒)")
        #expect(CommandNotification.body(exitCode: 1, durationNanos: eleven) == "失敗 (返り値 1, 11 秒)")
        #expect(CommandNotification.body(exitCode: nil, durationNanos: eleven) == "終了 (11 秒)")
    }
}

@Suite struct AppSettingsTests {
    @Test func tabBarFollowsSlideEdge() throws {
        let suite = "QuatermCoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.tabBarPosition == .top)
        defaults.set(SlideEdge.bottom.rawValue, forKey: SettingsKey.slideEdge)
        #expect(settings.tabBarEdge == .top)
        defaults.set(TabBarPosition.followSlideEdge.rawValue, forKey: SettingsKey.tabBarPosition)
        #expect(settings.tabBarEdge == .bottom)
        defaults.set(SlideEdge.top.rawValue, forKey: SettingsKey.slideEdge)
        #expect(settings.tabBarEdge == .top)
        defaults.set(TabBarPosition.bottom.rawValue, forKey: SettingsKey.tabBarPosition)
        #expect(settings.tabBarEdge == .bottom)
    }

    @Test func defaultsAndClamping() throws {
        let suite = "QuatermCoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.heightRatio == Constants.defaultHeightRatio)
        #expect(settings.slideEdge == .top)
        #expect(settings.displayMode == .active)
        #expect(settings.fallbackDisplay == nil)
        #expect(settings.confirmQuit)
        #expect(settings.confirmCloseLastTab)
        #expect(!settings.translucent)
        #expect(settings.backgroundOpacity == 1)
        settings.translucent = true
        #expect(settings.backgroundOpacity == Constants.defaultTranslucentOpacity)
        defaults.set(0.05, forKey: SettingsKey.translucentOpacity)
        #expect(settings.backgroundOpacity == 0.2)

        settings.heightRatio = 5
        #expect(settings.heightRatio == 1.0)
        settings.fallbackDisplay = .main
        #expect(settings.fallbackDisplay == .main)

        // The preferences picker stores "" for "not selected".
        defaults.set("", forKey: SettingsKey.specificDisplayID)
        #expect(settings.specificDisplayID == nil)
    }
}

@Suite struct GhosttyConfigTests {
    @Test func copyOnSelectAndScrollback() {
        let on = Dictionary(
            GhosttyConfig.entries(scrollbackLines: 1000, copyOnSelect: true, backgroundOpacity: 0.8, fontFamily: "", fontSize: 14).filter {
                $0.key != "keybind"
            },
            uniquingKeysWith: { a, _ in a }
        )
        #expect(on["copy-on-select"] == "clipboard")
        #expect(on["background-opacity"] == "0.8")
        #expect(on["scrollback-limit-lines"] == "1000")
        let off = GhosttyConfig.entries(
            scrollbackLines: 1000, copyOnSelect: false, backgroundOpacity: 1, fontFamily: "Menlo", fontSize: 100)
        #expect(off.contains { $0 == ("copy-on-select", "none") })
        #expect(off.contains { $0 == ("background-opacity", "1.0") })
        // A chosen font replaces the default instead of becoming a fallback; size is clamped.
        #expect(Array(off.prefix(2)).elementsEqual([("font-family", ""), ("font-family", "Menlo")]) { $0 == $1 })
        #expect(off.contains { $0 == ("font-size", "72.0") })
        let defaultFont = GhosttyConfig.entries(
            scrollbackLines: 1000, copyOnSelect: false, backgroundOpacity: 1, fontFamily: "", fontSize: 14)
        #expect(!defaultFont.contains { $0.key == "font-family" })
    }
}

@Suite struct TabNavigationTests {
    @Test func nextAndPreviousWrapAround() {
        #expect(TabNavigation.cycledIndex(from: 0, by: 1, count: 3) == 1)
        #expect(TabNavigation.cycledIndex(from: 2, by: 1, count: 3) == 0)
        #expect(TabNavigation.cycledIndex(from: 0, by: -1, count: 3) == 2)
        #expect(TabNavigation.cycledIndex(from: 0, by: 1, count: 1) == 0)
        #expect(TabNavigation.cycledIndex(from: 0, by: 1, count: 0) == nil)
    }
}

@Suite struct GhosttyUserConfigTests {
    let home = URL(fileURLWithPath: "/Users/me")

    @Test func candidatesFollowGhosttyOrderAndXDG() {
        let paths = GhosttyUserConfig.candidateURLs(home: home, environment: [:]).map(\.path)
        #expect(
            paths == [
                "/Users/me/.config/ghostty/config.ghostty",
                "/Users/me/.config/ghostty/config",
                "/Users/me/Library/Application Support/com.mitchellh.ghostty/config.ghostty",
                "/Users/me/Library/Application Support/com.mitchellh.ghostty/config",
            ])
        let xdg = GhosttyUserConfig.candidateURLs(home: home, environment: ["XDG_CONFIG_HOME": "/x"])
        #expect(xdg.first?.path == "/x/ghostty/config.ghostty")
        let empty = GhosttyUserConfig.candidateURLs(home: home, environment: ["XDG_CONFIG_HOME": ""])
        #expect(empty.first?.path == "/Users/me/.config/ghostty/config.ghostty")
    }

    @Test func diagnosedLinesComeFromTheFileOnly() {
        let lines = GhosttyUserConfig.diagnosedLines(
            ["/t/a.conf:29:keybind: unknown error", "/t/a.conf:3:font: bad", "/t/b.conf:7:x: y", "no line"],
            file: "/t/a.conf")
        #expect(lines == [29, 3])
    }

    @Test func themeNamePerAppearance() {
        #expect(GhosttyUserConfig.themeName("Dracula", dark: true) == "Dracula")
        #expect(GhosttyUserConfig.themeName("\"Catppuccin Mocha\"", dark: false) == "Catppuccin Mocha")
        #expect(GhosttyUserConfig.themeName("light:Alabaster, dark:Dracula", dark: false) == "Alabaster")
        #expect(GhosttyUserConfig.themeName("light:Alabaster, dark:Dracula", dark: true) == "Dracula")
        #expect(
            GhosttyUserConfig.themesDirectory(home: home, environment: [:]).path == "/Users/me/.config/ghostty/themes")
    }

    @Test func editableIsLastExistingElsePlainXDG() {
        let candidates = GhosttyUserConfig.candidateURLs(home: home, environment: [:])
        #expect(GhosttyUserConfig.editableURL(existing: [], candidates: candidates) == candidates[1])
        #expect(GhosttyUserConfig.editableURL(existing: [candidates[0], candidates[3]], candidates: candidates) == candidates[3])
    }

    @Test func parsesEntriesAndSkipsComments() {
        let contents = """
            # comment
            theme = Dracula

              cursor-style=bar
            keybind = ctrl+a=text:\\x01
            font-thicken
            = orphan
            """
        let entries = GhosttyUserConfig.entries(contents: contents)
        #expect(entries.map(\.key) == ["theme", "cursor-style", "keybind", "font-thicken"])
        #expect(entries.map(\.value) == ["Dracula", "bar", "ctrl+a=text:\\x01", "true"])
    }

    struct ReadFailed: Error {}

    @Test func includesAreSplicedAfterTheirFile() {
        let files: [String: String] = [
            "/c/main": "config-file = dropped\nconfig-file =\nconfig-file = colors\nconfig-file = ?\"../none\"\nfont-size = 13",
            "/c/colors": "background = 000000",
        ]
        let loaded = GhosttyUserConfig.load(files: [URL(fileURLWithPath: "/c/main"), URL(fileURLWithPath: "/c/absent")]) {
            files[$0.path]
        }
        #expect(loaded.problems.isEmpty)
        #expect(loaded.entries == [.init(key: "font-size", value: "13"), .init(key: "background", value: "000000")])
    }

    @Test func includesComeAfterEveryListedFile() {
        let files: [String: String] = [
            "/a/config": "config-file = inc\nfont-size = 1",
            "/a/inc": "config-file = deep\nfont-size = 3",
            "/b/config": "font-size = 2",
            "/a/deep": "font-size = 4",
        ]
        let loaded = GhosttyUserConfig.load(files: [URL(fileURLWithPath: "/a/config"), URL(fileURLWithPath: "/b/config")]) {
            files[$0.path]
        }
        #expect(loaded.entries.map(\.value) == ["1", "2", "3", "4"])
        // A reset in a later file drops the includes the earlier files queued.
        var reset = files
        reset["/b/config"] = "config-file =\nfont-size = 2"
        let cleared = GhosttyUserConfig.load(files: [URL(fileURLWithPath: "/a/config"), URL(fileURLWithPath: "/b/config")]) {
            reset[$0.path]
        }
        #expect(cleared.entries.map(\.value) == ["1", "2"])
    }

    @Test func pathValuesBecomeAbsolute() {
        let loaded = GhosttyUserConfig.load(files: [URL(fileURLWithPath: "/a/config")]) { _ in
            "custom-shader = shaders/crt.glsl\nbackground-image = ?/img/bg.png\ncursor-style = bar"
        }
        #expect(loaded.entries.map(\.value) == ["/a/shaders/crt.glsl", "?/img/bg.png", "bar"])
    }

    @Test func badFilesAreReported() {
        let files: [String: String] = [
            "/c/main": "config-file = missing\nconfig-file = main\nconfig-file = locked"
        ]
        // /c/missing is also an optional candidate: being absent there must not hide the include.
        let candidates = [URL(fileURLWithPath: "/c/missing"), URL(fileURLWithPath: "/c/main")]
        let loaded = GhosttyUserConfig.load(files: candidates) { url in
            if url.path == "/c/locked" { throw ReadFailed() }
            return files[url.path]
        }
        #expect(
            loaded.problems == [
                Messages.ghosttyConfigMissing("/c/missing"),
                Messages.ghosttyConfigUnreadable("/c/locked"),
            ])
    }

    @Test func includePaths() {
        let dir = URL(fileURLWithPath: "/Users/me/.config/ghostty")
        #expect(GhosttyUserConfig.filePath("colors", directory: dir)?.url.path == "/Users/me/.config/ghostty/colors")
        #expect(GhosttyUserConfig.filePath("colors", directory: dir)?.required == true)
        let optional = GhosttyUserConfig.filePath("?\"../shared/keys\"", directory: dir)
        #expect(optional?.url.path == "/Users/me/.config/shared/keys")
        #expect(optional?.required == false)
        #expect(GhosttyUserConfig.filePath("/etc/ghostty", directory: dir)?.url.path == "/etc/ghostty")
        #expect(GhosttyUserConfig.filePath("", directory: dir) == nil)
    }
}
