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

        let content = NSView()
        tabBar.autoresizingMask = [.width, .minYMargin]
        container.autoresizingMask = [.width, .height]
        content.addSubview(container)
        content.addSubview(tabBar)
        panel.contentView = content
        layoutContent(size: .zero)

        store.onSelect = { [weak self] in self?.selectTab($0) }
        store.onClose = { [weak self] in self?.closeTab($0) }
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
        }
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
    func withAutoHideSuppressed<T>(_ body: () -> T) -> T {
        suppressAutoHide = true
        defer {
            suppressAutoHide = false
            if isShown {
                panel.makeKey()
                focusSelectedTerminal()
            }
        }
        return body()
    }

    func windowDidResignKey(_: Notification) {
        guard isShown, !store.isPinned, !suppressAutoHide else { return }
        hide()
    }

    // MARK: AppSettings

    func applySettings() {
        ghostty.setTerminalConfiguration(Self.configuration(settings))
        guard isShown, let screen = panel.screen ?? resolveScreen() else { return }
        let frame = shownFrame(on: screen)
        layoutContent(size: frame.size)
        panel.setFrame(frame, display: true)
    }

    private static func configuration(_ settings: AppSettings) -> TerminalConfiguration {
        TerminalConfiguration(startingFrom: .default) { builder in
            for entry in GhosttyConfig.entries(scrollbackLines: settings.scrollbackLines, copyOnSelect: settings.copyOnSelect) {
                builder.withCustom(entry.key, entry.value)
            }
        }
    }

    // MARK: Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        if KeyboardShortcuts.Shortcut(event: event) == .quit {
            NSApp.terminate(nil)
            return true
        }
        guard let action = LocalAction.matching(event) else { return false }
        switch action {
        case .togglePin: togglePin()
        case .newTab: newTab()
        case .closeTab: store.selectedID.map(closeTab)
        case .growWindow: resize(steps: 1)
        case .shrinkWindow: resize(steps: -1)
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

    private func focusSelectedTerminal() {
        guard let id = store.selectedID, let view = tabs[id]?.view else { return }
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
        NSApp.activate()
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
