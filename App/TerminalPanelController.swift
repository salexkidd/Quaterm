import AppKit
import GhosttyTerminal
import KeyboardShortcuts
import QuatermCore
import SwiftUI

/// Borderless panel that can take keyboard focus without activating the app,
/// so the app the user was in stays active underneath.
private final class TerminalPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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
    /// The app that was active before an alert activated Quaterm; handed the keyboard back on hide.
    private var appToRestore: NSRunningApplication?
    /// Set while a modal alert owns the keyboard, so losing key status does not hide the panel.
    private var suppressAutoHide = false

    init(settings: AppSettings, notifier: Notifier) {
        self.settings = settings
        self.notifier = notifier
        ghostty = TerminalController(configuration: Self.configuration(settings))
        let store = TabStore()
        self.store = store
        tabBar = NSHostingView(rootView: TabBar(store: store))
        panel = TerminalPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
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
        applyPinLevel()
        applyTranslucency()

        let content = NSView()
        tabBar.autoresizingMask = [.width, .minYMargin]
        container.autoresizingMask = [.width, .height]
        content.addSubview(container)
        content.addSubview(tabBar)
        panel.contentView = content
        layoutContent(size: .zero)

        store.onSelect = { [weak self] in self?.selectTab($0) }
        store.onClose = { [weak self] in self?.closeTabAsked($0) }
        store.onNewTab = { [weak self] in self?.newTab() }
        store.onTogglePin = { [weak self] in self?.togglePin() }

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
        if tabs.isEmpty { newTab() }

        let shown = shownFrame(on: screen)
        let fade = settings.fade
        if !panel.isVisible {
            panel.setFrame(WindowGeometry.hiddenFrame(shown: shown, screen: screen.frame, edge: settings.slideEdge), display: false)
            panel.alphaValue = fade ? 0 : 1
        }
        layoutContent(size: shown.size)
        panel.orderFrontRegardless()
        panel.makeKey()
        focusSelectedTerminal()
        animate(to: shown, alpha: 1)
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        let screenFrame = (panel.screen ?? NSScreen.screens.first)?.frame ?? panel.frame
        let hidden = WindowGeometry.hiddenFrame(shown: panel.frame, screen: screenFrame, edge: settings.slideEdge)
        animate(to: hidden, alpha: settings.fade ? 0 : 1) { [weak self] in
            guard let self, !isShown else { return }
            panel.orderOut(nil)
            restorePreviousApp()
        }
    }

    /// After an alert made Quaterm active, give the keyboard back to the app the user was in,
    /// unless another Quaterm window (Preferences) is open and should keep it.
    private func restorePreviousApp() {
        defer { appToRestore = nil }
        let otherWindowOpen = NSApp.windows.contains { $0 !== panel && $0.isVisible && $0.canBecomeMain }
        guard NSApp.isActive, !otherWindowOpen else { return }
        appToRestore?.activate()
    }

    private func animate(to frame: NSRect, alpha: CGFloat, completion: (@MainActor @Sendable () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = settings.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }

    /// Runs a modal step (an alert) without the panel hiding when it loses key status,
    /// then gives the keyboard back to the panel if it is still shown.
    /// The app is activated so the alert gets the keyboard (the panel never activates it),
    /// and a pinned panel drops below the alert so it cannot cover it.
    func withAutoHideSuppressed<T>(_ body: () -> T) -> T {
        suppressAutoHide = true
        panel.level = .floating
        if !NSApp.isActive {
            appToRestore = NSWorkspace.shared.frontmostApplication
        }
        NSApp.activate()
        defer {
            suppressAutoHide = false
            applyPinLevel()
            if isShown {
                panel.makeKey()
                focusSelectedTerminal()
            } else {
                restorePreviousApp()
            }
        }
        return body()
    }

    func windowDidResignKey(_: Notification) {
        guard isShown, !store.isPinned, !suppressAutoHide else { return }
        hide()
    }

    // MARK: Settings

    func applySettings() {
        ghostty.setTerminalConfiguration(Self.configuration(settings))
        applyTranslucency()
        guard isShown, let screen = panel.screen ?? resolveScreen() else { return }
        let frame = shownFrame(on: screen)
        layoutContent(size: frame.size)
        panel.setFrame(frame, display: true)
    }

    /// Ghostty draws the translucent background; the window itself must be see-through for it to show.
    private func applyTranslucency() {
        let translucent = settings.translucent
        panel.isOpaque = !translucent
        panel.backgroundColor = translucent ? .clear : .windowBackgroundColor
    }

    private static func configuration(_ settings: AppSettings) -> TerminalConfiguration {
        TerminalConfiguration(startingFrom: .default) { builder in
            let entries = GhosttyConfig.entries(
                scrollbackLines: settings.scrollbackLines,
                copyOnSelect: settings.copyOnSelect,
                translucent: settings.translucent
            )
            for entry in entries {
                builder.withCustom(entry.key, entry.value)
            }
        }
    }

    // MARK: Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        // Fixed keys. The main menu has them too, but it does not see keys sent to this
        // non-activating panel while another app is active.
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
        applyPinLevel()
    }

    private func applyPinLevel() {
        // Both levels sit below the screen saver.
        panel.level = store.isPinned ? .statusBar : .floating
    }

    private func resize(steps: Int) {
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
        alert.addButton(withTitle: Messages.cancelButton)
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
        container.frame = NSRect(x: 0, y: 0, width: size.width, height: max(0, size.height - barHeight))
        tabBar.frame = NSRect(x: 0, y: max(0, size.height - barHeight), width: size.width, height: barHeight)
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
            settings.fallbackDisplay = askFallbackDisplay()
            resolution = resolve()
        }
        guard case let .display(id)? = resolution else { return screens.first }
        return screens.first { $0.displayUUID == id } ?? screens.first
    }

    private func askFallbackDisplay() -> FallbackDisplay {
        let alert = NSAlert()
        alert.messageText = Messages.displayMissingTitle
        alert.informativeText = Messages.displayMissingInfo
        alert.addButton(withTitle: Messages.activeDisplay)
        alert.addButton(withTitle: Messages.mainDisplay)
        return withAutoHideSuppressed { alert.runModal() } == .alertSecondButtonReturn ? .main : .active
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
