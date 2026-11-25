import AppKit
import GhosttyKit
import GhosttyTerminal
import GhosttyTheme
import KeyboardShortcuts
import QuatermCore
import SwiftUI

/// Borderless panel that can take keyboard focus.
private final class TerminalPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Content view that repaints its background when light / dark mode changes.
private final class ContentView: NSView {
    var onAppearanceChange: () -> Void = {}

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange()
    }
}

/// One tab: a Ghostty surface running the user's shell.
@MainActor
private final class TerminalTab:
    TerminalSurfaceTitleDelegate,
    TerminalSurfaceCloseDelegate,
    TerminalSurfaceCommandFinishedDelegate
{
    let id = UUID()
    let view = TerminalView(frame: .zero)
    weak var owner: TerminalPanelController?

    init(controller: TerminalController, owner: TerminalPanelController) {
        self.owner = owner
        view.delegate = self
        view.configuration = TerminalSurfaceOptions(backend: .exec, workingDirectory: NSHomeDirectory())
        view.controller = controller
        view.autoresizingMask = [.width, .height]
    }

    func terminalDidChangeTitle(_ title: String) {
        owner?.tabTitleChanged(id, title: title)
    }

    func terminalDidClose(processAlive _: Bool) {
        owner?.closeTab(id)
    }

    func terminalDidFinishCommand(exitCode: Int?, durationNanos: UInt64) {
        owner?.commandFinished(exitCode: exitCode, durationNanos: durationNanos)
    }
}

@MainActor
final class TerminalPanelController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let notifier: Notifier
    private let panel: TerminalPanel
    private let container = NSView()
    private let tabBar: NSHostingView<TabBar>
    private let store: TabStore
    private let ghostty: TerminalController
    private var tabs: [UUID: TerminalTab] = [:]
    private var keyMonitor: Any?

    /// True from the moment show starts until hide starts (animations included).
    private(set) var isShown = false
    /// Opens the preferences window; set by the app delegate.
    var onShowPreferences: () -> Void = {}
    /// The app the user was in most recently, other than Quaterm; gets the keyboard back
    /// when the panel hides. Updated on every activation so it is never stale.
    private var lastOtherApp = NSWorkspace.shared.frontmostApplication
    private var activationObserver: Any?
    /// Set when show() activates Quaterm: activation finishes later and AppKit then restores the
    /// app's previous key window (Preferences), so the panel takes the key back at that point.
    private var takeKeyOnActivation = false
    private var becomeActiveObserver: Any?
    private var resignActiveObserver: Any?
    private var resignKeyObserver: Any?
    /// Set while a modal alert owns the keyboard, so losing key status does not hide the panel.
    private var suppressAutoHide = false

    init(settings: AppSettings, notifier: Notifier) {
        self.settings = settings
        self.notifier = notifier
        ghostty = TerminalController(configuration: .default, theme: Self.theme(settings, user: []))
        let store = TabStore()
        self.store = store
        tabBar = NSHostingView(rootView: TabBar(store: store))
        panel = TerminalPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // One level whether pinned or not, shared with Preferences: whichever window was brought
        // forward last is on top. Pinning only decides whether a click elsewhere hides the panel.
        panel.level = Self.shownLevel
        // The window itself stays clear: the content view paints the background and carries the
        // fade, which animates reliably where the window's own alpha does not.
        panel.isOpaque = false
        panel.backgroundColor = .clear

        let content = ContentView()
        content.wantsLayer = true
        tabBar.autoresizingMask = [.width, .minYMargin]
        container.autoresizingMask = [.width, .height]
        content.addSubview(container)
        content.addSubview(tabBar)
        panel.contentView = content
        applyTranslucency()
        layoutContent(size: .zero)
        applyTerminalConfiguration()

        store.onSelect = { [weak self] in self?.selectTab($0) }
        store.onClose = { [weak self] in self?.closeTabAsked($0) }
        store.onNewTab = { [weak self] in self?.newTab() }
        store.onTogglePin = { [weak self] in self?.togglePin() }

        content.onAppearanceChange = { [weak self] in self?.applyTranslucency() }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app, app != .current else { return }
                self.lastOtherApp = app
            }
        }

        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.takeKeyOnActivation else { return }
                self.takeKeyOnActivation = false
                guard self.isShown else { return }
                self.panel.makeKey()
                self.focusSelectedTerminal()
            }
        }

        // Unpinned, the panel hides when the user moves to another app. Moving to Quaterm's own
        // Preferences keeps the app active, so it does not hide the panel.
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isShown, !self.store.isPinned, !self.suppressAutoHide else { return }
                self.hide()
            }
        }

        // Another app's non-activating panel (Raycast, Spotlight) can take the keyboard while Quaterm
        // stays active. Whichever Quaterm window had it (the panel or Preferences), the panel hides
        // once no Quaterm window has the key. Checked on the next turn, after the new key is set.
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let resigned = note.object as? NSWindow
            DispatchQueue.main.async {
                guard let self, self.isShown, !self.store.isPinned, !self.suppressAutoHide, NSApp.keyWindow == nil
                else { return }
                // Closing Preferences may leave no key window; the terminal takes it back instead of hiding.
                if let resigned, resigned !== self.panel, !resigned.isVisible, NSApp.isActive {
                    self.panel.makeKey()
                    self.focusSelectedTerminal()
                } else {
                    self.hide()
                }
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === panel else { return event }
            return handleKey(event) ? nil : event
        }
    }

    // MARK: Show / hide

    func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        guard let screen = resolveScreen() else { return }
        isShown = true
        // Picks up edits to the Ghostty config file; a no-op when nothing changed.
        applyTerminalConfiguration()
        if tabs.isEmpty { newTab() }

        let shown = shownFrame(on: screen)
        let fade = settings.fade
        if !panel.isVisible {
            panel.setFrame(WindowGeometry.hiddenFrame(shown: shown, screen: screen.frame, edge: settings.slideEdge), display: false)
            panel.contentView?.alphaValue = fade ? 0 : 1
        }
        // Slide under the menu bar, then rise to the shared level once in place.
        panel.level = Self.slidingLevel
        layoutContent(size: shown.size)
        // Quaterm becomes the active app so the menu bar is its own; hide() hands focus back.
        takeKeyOnActivation = !NSApp.isActive
        NSApp.activate()
        panel.orderFrontRegardless()
        panel.makeKey()
        focusSelectedTerminal()
        animate(to: shown, alpha: 1) { [weak self] in
            // During an alert the level stays lowered; the alert's cleanup raises it.
            guard let self, isShown, !suppressAutoHide else { return }
            panel.level = Self.shownLevel
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        let screenFrame = (panel.screen ?? NSScreen.screens.first)?.frame ?? panel.frame
        let hidden = WindowGeometry.hiddenFrame(shown: panel.frame, screen: screenFrame, edge: settings.slideEdge)
        panel.level = Self.slidingLevel
        animate(to: hidden, alpha: settings.fade ? 0 : 1) { [weak self] in
            guard let self, !isShown else { return }
            // Hand the keyboard back only if the user was in the terminal, not in Preferences.
            // Checked before ordering out, which would pass the key to an open Preferences window.
            let stillInTerminal = panel.isKeyWindow
            panel.orderOut(nil)
            panel.level = Self.shownLevel
            if stillInTerminal { restorePreviousApp() }
        }
    }

    /// Give the keyboard back to the app the user was in before Quaterm.
    private func restorePreviousApp() {
        guard NSApp.isActive else { return }
        lastOtherApp?.activate()
    }

    private func animate(to frame: NSRect, alpha: CGFloat, completion: (@MainActor @Sendable () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = settings.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.contentView?.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }

    /// Runs a modal step (an alert) without the panel hiding when it loses key status,
    /// then gives the keyboard back to the panel if it is still shown.
    /// The app is activated so the alert gets the keyboard (the panel never activates it),
    /// and Quaterm's raised windows (the panel, Preferences) drop to the normal level so none covers the alert.
    func withAutoHideSuppressed<T>(_ body: () -> T) -> T {
        suppressAutoHide = true
        // canBecomeMain leaves out the menu bar icon's window, which must keep its level.
        let raised = NSApp.windows.filter { $0.canBecomeMain && $0.level > .normal }
        let savedLevels = raised.map { ($0, $0.level) }
        raised.forEach { $0.level = .normal }
        // The window that had the keyboard before the alert gets it back (Preferences, or the panel).
        let previousKey = NSApp.keyWindow
        NSApp.activate()
        defer {
            suppressAutoHide = false
            for (window, level) in savedLevels where window !== panel { window.level = level }
            // The panel's level depends on where it is now, not on what it was when the alert opened
            // (a slide may have finished meanwhile).
            panel.level = isShown ? Self.shownLevel : Self.slidingLevel
            // The user may have switched apps while the alert was open; that deactivation was ignored.
            if isShown, !store.isPinned, !NSApp.isActive {
                hide()
            } else if let previousKey, previousKey !== panel, previousKey.isVisible {
                previousKey.makeKeyAndOrderFront(nil)
            } else if isShown {
                panel.makeKey()
                focusSelectedTerminal()
            } else {
                restorePreviousApp()
            }
        }
        return body()
    }

    // MARK: Settings

    func applySettings() {
        applyTerminalConfiguration()
        applyTranslucency()
        guard isShown, let screen = panel.screen ?? resolveScreen() else { return }
        let frame = shownFrame(on: screen)
        layoutContent(size: frame.size)
        panel.setFrame(frame, display: true)
    }

    /// Ghostty draws the translucent background; the window itself must be see-through for it to show.
    private func applyTranslucency() {
        guard let content = panel.contentView else { return }
        // cgColor freezes the color for the current appearance, so resolve it under the view's own.
        content.effectiveAppearance.performAsCurrentDrawingAppearance {
            content.layer?.backgroundColor = settings.translucent ? .clear : NSColor.windowBackgroundColor.cgColor
        }
    }

    /// Shared with Preferences while shown; below the screen saver.
    private static let shownLevel = NSWindow.Level.statusBar
    /// Below the menu bar, so the slide passes under it instead of covering it.
    private static let slidingLevel = NSWindow.Level.floating

    /// The user config and alert last reported, so each alert shows once per edit.
    private var reported: (user: GhosttyUserConfig.Loaded, title: String)?
    /// Lines last screened, and the result, so an unchanged config is not checked again.
    private var screened: (entries: [GhosttyUserConfig.Entry], kept: [GhosttyUserConfig.Entry], skipped: [String])?

    /// The user's Ghostty config files, then Quaterm's settings on top.
    private func applyTerminalConfiguration() {
        let files = FileManager.default
        let user = GhosttyUserConfig.load(
            files: GhosttyUserConfig.candidateURLs(
                home: files.homeDirectoryForCurrentUser, environment: ProcessInfo.processInfo.environment)
        ) { url in
            files.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : nil
        }
        var problems = user.problems
        if problems.isEmpty {
            if screened?.entries != user.entries {
                let result = Self.screen(user.entries)
                screened = (user.entries, result.kept, result.skipped)
            }
            let kept = screened?.kept ?? user.entries
            let skipped = screened?.skipped ?? []
            let wanted = Self.theme(settings, user: kept)
            ghostty.setTheme(wanted)
            if ghostty.theme == wanted {
                if skipped.isEmpty {
                    reported = nil
                } else {
                    report(user, title: Messages.ghosttyConfigSkippedTitle, info: Messages.ghosttyConfigSkippedInfo(skipped))
                }
                return
            }
            // Still rejected as a whole, by something no single line shows.
            problems = [ghostty.lastConfigurationIssue ?? ""]
        }
        // Keep running on Quaterm's own settings and say why.
        ghostty.setTheme(Self.theme(settings, user: []))
        report(
            user, title: Messages.ghosttyConfigRejectedTitle,
            info: Messages.ghosttyConfigRejectedInfo(problems.joined(separator: "\n")))
    }

    private func report(_ user: GhosttyUserConfig.Loaded, title: String, info: String) {
        guard reported?.user != user || reported?.title != title else { return }
        reported = (user, title)
        // Not from inside show(): the alert must not interrupt the panel half-way through showing.
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = info
            self?.withAutoHideSuppressed { _ = alert.runModal() }
        }
    }

    /// libghostty-spm rejects a whole config over one bad line, where Ghostty itself skips the
    /// line. Lines libghostty does not accept (often keys or actions newer than it) are found
    /// here by loading the user's lines alone, and left out. `theme` lines are resolved later,
    /// per appearance, so they are not checked here.
    private static func screen(_ entries: [GhosttyUserConfig.Entry]) -> (kept: [GhosttyUserConfig.Entry], skipped: [String]) {
        let checked = entries.indices.filter { entries[$0].key != "theme" }
        let url = FileManager.default.temporaryDirectory.appending(path: "quaterm-check-\(UUID().uuidString).conf")
        let text = checked.map { "\(entries[$0].key) = \(entries[$0].value)" }.joined(separator: "\n")
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil, let config = ghostty_config_new() else {
            return (entries, [])
        }
        defer {
            ghostty_config_free(config)
            try? FileManager.default.removeItem(at: url)
        }
        ghostty_config_load_file(config, url.path)
        let diagnostics = (0..<ghostty_config_diagnostics_count(config)).compactMap { index -> String? in
            let message: UnsafePointer<CChar>? = ghostty_config_get_diagnostic(config, index).message
            return message.map { String(cString: $0) }
        }
        let bad = Set(
            GhosttyUserConfig.diagnosedLines(diagnostics, file: url.path)
                .filter { checked.indices.contains($0 - 1) }
                .map { checked[$0 - 1] })
        let kept = entries.indices.filter { !bad.contains($0) }.map { entries[$0] }
        let skipped = bad.sorted().map { "\(entries[$0].key) = \(entries[$0].value)" }
        return (kept, skipped)
    }

    /// Everything goes in the theme, because libghostty writes the theme last: put anywhere else,
    /// the default colors would override the user's. They stay first instead, and are left out
    /// when the user picks a `theme`, since Ghostty lets explicit colors win over a theme.
    private static func theme(_ settings: AppSettings, user: [GhosttyUserConfig.Entry]) -> TerminalTheme {
        let colors = user.contains { $0.key == "theme" } ? TerminalTheme() : .default
        return TerminalTheme(
            light: configuration(settings, user: resolvingThemes(user, dark: false), startingFrom: colors.light),
            dark: configuration(settings, user: resolvingThemes(user, dark: true), startingFrom: colors.dark)
        )
    }

    /// Turns `theme` lines into plain color lines placed first, so the user's own color lines
    /// still win as they do over a theme in Ghostty, and the last `theme` wins. A theme file (a
    /// path, or a name in the user's themes folder) is read here, so editing it shows the next
    /// time the terminal does. A built-in name comes from the package's theme catalog, since
    /// libghostty-spm ships no folder of built-in themes. An unknown name is left for Ghostty to
    /// reject, which the caller reports.
    private static func resolvingThemes(_ user: [GhosttyUserConfig.Entry], dark: Bool) -> [GhosttyUserConfig.Entry] {
        let themes = GhosttyUserConfig.themesDirectory(
            home: FileManager.default.homeDirectoryForCurrentUser, environment: ProcessInfo.processInfo.environment)
        var colors: [GhosttyUserConfig.Entry] = []
        var rest: [GhosttyUserConfig.Entry] = []
        for entry in user {
            guard entry.key == "theme" else {
                rest.append(entry)
                continue
            }
            let name = GhosttyUserConfig.themeName(entry.value, dark: dark)
            rest.removeAll { $0.key == "theme" }
            let file = name.hasPrefix("/") ? URL(fileURLWithPath: name) : themes.appending(path: name)
            if let contents = try? String(contentsOf: file, encoding: .utf8) {
                colors = GhosttyUserConfig.entries(contents: contents)
            } else if let builtIn = GhosttyThemeCatalog.theme(named: name) {
                colors = GhosttyUserConfig.entries(contents: builtIn.toTerminalConfiguration().rendered)
            } else {
                colors = []
                rest.append(GhosttyUserConfig.Entry(key: "theme", value: name))
            }
        }
        return colors + rest
    }

    private static func configuration(
        _ settings: AppSettings, user: [GhosttyUserConfig.Entry], startingFrom colors: TerminalConfiguration
    ) -> TerminalConfiguration {
        TerminalConfiguration(startingFrom: colors) { builder in
            for entry in user {
                builder.withCustom(entry.key, entry.value)
            }
            let entries = GhosttyConfig.entries(
                scrollbackLines: settings.scrollbackLines,
                copyOnSelect: settings.copyOnSelect,
                backgroundOpacity: settings.backgroundOpacity,
                fontFamily: settings.fontFamily,
                fontSize: settings.fontSize
            )
            for entry in entries {
                builder.withCustom(entry.key, entry.value)
            }
        }
    }

    // MARK: Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        // Fixed keys. The main menu has them too; matching them here first keeps them working
        // even if a terminal program would otherwise take the key.
        switch KeyboardShortcuts.Shortcut(event: event) {
        case .quit?:
            NSApp.terminate(nil)
            return true
        case .preferences?:
            onShowPreferences()
            return true
        default:
            break
        }
        guard let action = LocalAction.matching(event) else { return false }
        switch action {
        case .togglePin: togglePin()
        case .newTab: newTab()
        case .closeTab: store.selectedID.map(closeTabAsked)
        case .nextTab: cycleTab(by: 1)
        case .previousTab: cycleTab(by: -1)
        case .growWindow: resize(steps: 1)
        case .shrinkWindow: resize(steps: -1)
        case .increaseFontSize: selectedView?.performBindingAction("increase_font_size:1")
        case .decreaseFontSize: selectedView?.performBindingAction("decrease_font_size:1")
        case .toggleTranslucent: settings.translucent.toggle()
        }
        return true
    }

    private func togglePin() {
        store.isPinned.toggle()
    }

    private func resize(steps: Int) {
        let steps = WindowGeometry.resizeSteps(steps, edge: settings.slideEdge)
        settings.heightRatio = WindowGeometry.resizedRatio(settings.heightRatio, steps: steps)
        // The UserDefaults change notification re-lays out the panel through applySettings().
    }

    // MARK: Tabs

    func newTab() {
        let tab = TerminalTab(controller: ghostty, owner: self)
        tabs[tab.id] = tab
        store.tabs.append(TabItem(id: tab.id, title: Messages.newTabTitle))
        selectTab(tab.id)
    }

    private func selectTab(_ id: UUID) {
        guard let tab = tabs[id] else { return }
        if let current = store.selectedID, current != id {
            tabs[current]?.view.removeFromSuperview()
        }
        store.selectedID = id
        if tab.view.superview !== container {
            tab.view.frame = container.bounds
            container.addSubview(tab.view)
        }
        focusSelectedTerminal()
    }

    private func cycleTab(by offset: Int) {
        guard let current = store.tabs.firstIndex(where: { $0.id == store.selectedID }),
            let index = TabNavigation.cycledIndex(from: current, by: offset, count: store.tabs.count)
        else { return }
        selectTab(store.tabs[index].id)
    }

    /// Closing by the user (Cmd+W, the X button). Asks first when it is the last tab.
    /// A shell that exits on its own closes its tab through `closeTab` without asking.
    private func closeTabAsked(_ id: UUID) {
        if store.tabs.count == 1, settings.confirmCloseLastTab, !confirmCloseLastTab() { return }
        closeTab(id)
    }

    private func confirmCloseLastTab() -> Bool {
        let alert = NSAlert()
        alert.messageText = Messages.closeLastTabTitle
        alert.informativeText = Messages.closeLastTabInfo
        alert.addButton(withTitle: Messages.closeButton)
        alert.addCancelButton()
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = Messages.dontAskAgain
        let confirmed = withAutoHideSuppressed { alert.runModal() } == .alertFirstButtonReturn
        if confirmed, alert.suppressionButton?.state == .on {
            settings.confirmCloseLastTab = false
        }
        return confirmed
    }

    fileprivate func closeTab(_ id: UUID) {
        guard let tab = tabs.removeValue(forKey: id),
            let index = store.tabs.firstIndex(where: { $0.id == id })
        else { return }
        tab.view.removeFromSuperview()
        store.tabs.remove(at: index)

        if store.tabs.isEmpty {
            store.selectedID = nil
            hide()
        } else if store.selectedID == id {
            store.selectedID = nil
            selectTab(store.tabs[min(index, store.tabs.count - 1)].id)
        }
    }

    fileprivate func tabTitleChanged(_ id: UUID, title: String) {
        guard let index = store.tabs.firstIndex(where: { $0.id == id }), !title.isEmpty else { return }
        store.tabs[index].title = title
    }

    fileprivate func commandFinished(exitCode: Int?, durationNanos: UInt64) {
        guard
            CommandNotification.shouldNotify(
                windowVisible: isShown,
                exitCode: exitCode,
                durationNanos: durationNanos,
                minSeconds: settings.notifyMinSeconds,
                result: settings.notifyResult
            )
        else { return }
        notifier.post(body: CommandNotification.body(exitCode: exitCode, durationNanos: durationNanos))
    }

    private var selectedView: TerminalView? {
        store.selectedID.flatMap { tabs[$0]?.view }
    }

    private func focusSelectedTerminal() {
        guard let view = selectedView else { return }
        panel.makeFirstResponder(view)
    }

    // MARK: Layout & displays

    private func layoutContent(size: NSSize) {
        guard let content = panel.contentView else { return }
        content.frame = NSRect(origin: .zero, size: size)
        let barHeight = Constants.tabBarHeight
        let terminalHeight = max(0, size.height - barHeight)
        // Content coordinates start at the bottom, so a bottom tab bar sits at y = 0.
        switch settings.tabBarEdge {
        case .top:
            container.frame = NSRect(x: 0, y: 0, width: size.width, height: terminalHeight)
            tabBar.frame = NSRect(x: 0, y: terminalHeight, width: size.width, height: barHeight)
        case .bottom:
            container.frame = NSRect(x: 0, y: barHeight, width: size.width, height: terminalHeight)
            tabBar.frame = NSRect(x: 0, y: 0, width: size.width, height: barHeight)
        }
    }

    private func shownFrame(on screen: NSScreen) -> NSRect {
        WindowGeometry.shownFrame(
            screen: screen.frame,
            visible: screen.visibleFrame,
            edge: settings.slideEdge,
            heightRatio: settings.heightRatio
        )
    }

    private func resolveScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let mouse = NSEvent.mouseLocation
        let displays = screens.map { screen in
            DisplayInfo(
                id: screen.displayUUID ?? "",
                isMain: screen == screens.first,
                containsMouse: NSMouseInRect(mouse, screen.frame, false)
            )
        }
        let resolve = {
            DisplayResolver.resolve(
                mode: self.settings.displayMode,
                specificID: self.settings.specificDisplayID,
                fallback: self.settings.fallbackDisplay,
                displays: displays
            )
        }
        var resolution = resolve()
        if resolution == .needsFallbackChoice {
            // Cancelled: use the active display this time and ask again next time.
            let choice = askFallbackDisplay()
            if let choice { settings.fallbackDisplay = choice }
            resolution = DisplayResolver.resolve(
                mode: settings.displayMode,
                specificID: settings.specificDisplayID,
                fallback: choice ?? .active,
                displays: displays
            )
        }
        guard case let .display(id)? = resolution else { return screens.first }
        return screens.first { $0.displayUUID == id } ?? screens.first
    }

    /// nil when cancelled.
    private func askFallbackDisplay() -> FallbackDisplay? {
        let alert = NSAlert()
        alert.messageText = Messages.displayMissingTitle
        alert.informativeText = Messages.displayMissingInfo
        alert.addButton(withTitle: Messages.activeDisplay)
        alert.addButton(withTitle: Messages.mainDisplay)
        alert.addCancelButton()
        return switch withAutoHideSuppressed({ alert.runModal() }) {
        case .alertFirstButtonReturn: .active
        case .alertSecondButtonReturn: .main
        default: nil
        }
    }
}

extension NSAlert {
    /// Adds a Cancel button that Esc also presses. AppKit gives Esc only to a button it
    /// recognizes as "Cancel", which a Japanese title is not.
    func addCancelButton() {
        addButton(withTitle: Messages.cancelButton).keyEquivalent = "\u{1b}"
    }
}

extension NSScreen {
    /// Stable across reconnects, unlike the CGDirectDisplayID.
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
