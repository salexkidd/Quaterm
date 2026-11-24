import AppKit
import KeyboardShortcuts
import QuatermCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private var terminal: TerminalPanelController!
    private var statusItem: NSStatusItem!
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        terminal = TerminalPanelController(settings: settings, notifier: Notifier())
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
        alert.addButton(withTitle: Messages.cancelButton)
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = Messages.dontAskAgain
        NSApp.activate()
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
            let window = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView()))
            window.title = Messages.preferencesTitle
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = window
        }
        NSApp.activate()
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menus

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: Messages.appName)
        let menu = NSMenu()
        menu.addItem(withTitle: Messages.menuToggle, action: #selector(toggleTerminal), keyEquivalent: "").target = self
        menu.addItem(withTitle: Messages.menuPreferences, action: #selector(showPreferences), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: Messages.menuQuit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = menu
        return item
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: Messages.menuPreferences, action: #selector(showPreferences), keyEquivalent: ",").target = self
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
