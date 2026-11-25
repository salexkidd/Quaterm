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
