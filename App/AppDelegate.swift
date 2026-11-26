import AppKit
import KeyboardShortcuts
import QuatermCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private var terminal: TerminalPanelController!
    private var statusItem: NSStatusItem!
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        terminal = TerminalPanelController(settings: settings, notifier: Notifier())
        terminal.onShowPreferences = { [weak self] in self?.showPreferences() }
        applyDockPolicy()
        NSApp.mainMenu = makeMainMenu()
        statusItem = makeStatusItem()

        KeyboardShortcuts.onKeyDown(for: .toggleTerminal) { [weak self] in
            self?.terminal.toggle()
        }
        KeyboardShortcuts.unregisterLocalShortcuts()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        terminal.show()
        return false
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard settings.confirmQuit else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = Messages.quitTitle
        alert.informativeText = Messages.quitInfo
        alert.addButton(withTitle: Messages.quitButton)
        alert.addCancelButton()
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = Messages.dontAskAgain
        let reply = terminal.withAutoHideSuppressed { alert.runModal() }
        guard reply == .alertFirstButtonReturn else { return .terminateCancel }
        if alert.suppressionButton?.state == .on {
            settings.confirmQuit = false
        }
        return .terminateNow
    }

    // MARK: AppSettings

    private var lastShowInDock: Bool?

    private func settingsChanged() {
        // A recorded shortcut is registered system-wide by the library; take the local ones back.
        KeyboardShortcuts.unregisterLocalShortcuts()
        applyDockPolicy()
        terminal.applySettings()
    }

    private func applyDockPolicy() {
        let show = settings.showInDock
        guard show != lastShowInDock else { return }
        lastShowInDock = show
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    @objc private func toggleTerminal() {
        terminal.toggle()
    }

    @objc private func showPreferences() {
        if preferencesWindow == nil {
            let window = NSWindow(contentViewController: Preferences.makeController())
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            // Behaves like an HIG panel: on the pinned terminal's level, so whichever was brought
            // forward last is on top, and hidden while another app is active.
            window.level = .statusBar
            window.hidesOnDeactivate = true
            window.center()
            preferencesWindow = window
        }
        NSApp.activate()
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showAbout() {
        // The panel is found as the window that is new on screen: keyWindow can still be nil here,
        // since activate() takes effect later. AppKit reuses the panel, so the level set once stays.
        let before = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
        // Same level as Preferences, so the pinned terminal does not cover it.
        for window in NSApp.windows where window.isVisible && !before.contains(ObjectIdentifier(window)) {
            window.level = .statusBar
            window.identifier = TerminalPanelController.raisedPanelIdentifier
        }
    }

    /// Opens the Ghostty config file in the default text editor, creating it if there is none.
    @objc private func openGhosttyConfig() {
        let files = FileManager.default
        let candidates = GhosttyUserConfig.candidateURLs(
            home: files.homeDirectoryForCurrentUser, environment: ProcessInfo.processInfo.environment)
        let url = GhosttyUserConfig.editableURL(existing: candidates.filter { files.fileExists(atPath: $0.path) }, candidates: candidates)
        do {
            if !files.fileExists(atPath: url.path) {
                try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(Messages.ghosttyConfigTemplate.utf8).write(to: url)
            }
        } catch {
            showOpenGhosttyConfigFailed(error)
            return
        }
        // The file has no extension, so ask for the plain-text editor rather than the file's own app.
        guard let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText) else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            DispatchQueue.main.async { self.showOpenGhosttyConfigFailed(error) }
        }
    }

    private func showOpenGhosttyConfigFailed(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = Messages.ghosttyConfigOpenFailedTitle
        alert.informativeText = error.localizedDescription
        terminal.withAutoHideSuppressed { _ = alert.runModal() }
    }

    // MARK: Menus

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: Messages.appName)
        let menu = NSMenu()
        menu.addItem(withTitle: Messages.menuAbout, action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: Messages.menuToggle, action: #selector(toggleTerminal), keyEquivalent: "").target = self
        menu.addItem(withTitle: Messages.menuPreferences, action: #selector(showPreferences), keyEquivalent: "").target = self
        menu.addItem(withTitle: Messages.menuOpenGhosttyConfig, action: #selector(openGhosttyConfig), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: Messages.menuQuit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = menu
        return item
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: Messages.menuAbout, action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: Messages.menuPreferences, action: #selector(showPreferences), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: Messages.menuOpenGhosttyConfig, action: #selector(openGhosttyConfig), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: Messages.menuQuit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(title: Messages.appName, action: nil, keyEquivalent: "")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Standard editing keys for the text fields in Preferences.
        let editMenu = NSMenu(title: Messages.menuEdit)
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: Messages.menuEdit, action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        main.addItem(editItem)

        return main
    }
}
