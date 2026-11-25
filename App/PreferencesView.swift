import AppKit
import KeyboardShortcuts
import QuatermCore
import SwiftUI

/// Preferences as HIG asks for on macOS: a toolbar of panes, the window titled after the pane shown.
@MainActor
enum Preferences {
    static func makeController() -> NSViewController {
        // Read before adding panes: adding one can report a selection and overwrite the value.
        let lastPane = UserDefaults.standard.integer(forKey: SettingsKey.lastPreferencesPane)
        let tabs = PaneTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(pane("一般", symbol: "gearshape", GeneralPane()))
        tabs.addTabViewItem(pane("ショートカット", symbol: "keyboard", ShortcutsPane()))
        tabs.addTabViewItem(pane("ウィンドウ", symbol: "macwindow", WindowPane()))
        tabs.addTabViewItem(pane("ディスプレイ", symbol: "display", DisplayPane()))
        tabs.addTabViewItem(pane("フォント", symbol: "textformat", FontPane()))
        tabs.addTabViewItem(pane("ターミナル", symbol: "terminal", TerminalPane()))
        tabs.addTabViewItem(pane("通知", symbol: "bell", NotificationsPane()))
        tabs.selectedTabViewItemIndex = min(max(lastPane, 0), tabs.tabViewItems.count - 1)
        return tabs
    }

    private static func pane(_ title: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: PaneContainer(content: view))
        // The window follows each pane's own height instead of the tallest one.
        controller.sizingOptions = [.preferredContentSize]
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}

/// Remembers the pane shown, so Preferences reopens on it (HIG).
private final class PaneTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        UserDefaults.standard.set(selectedTabViewItemIndex, forKey: SettingsKey.lastPreferencesPane)
    }
}

private struct PaneContainer<Content: View>: View {
    let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralPane: View {
    @AppStorage(SettingsKey.showInDock) private var showInDock = true
    @AppStorage(SettingsKey.confirmQuit) private var confirmQuit = true
    @AppStorage(SettingsKey.confirmCloseLastTab) private var confirmCloseLastTab = true

    var body: some View {
        Section {
            Toggle("Dock にアイコンを表示する", isOn: $showInDock)
        }
        Section("確認ダイアログ") {
            Toggle("終了時に確認する", isOn: $confirmQuit)
            Toggle("最後のタブを閉じるときに確認する", isOn: $confirmCloseLastTab)
        }
    }
}

private struct ShortcutsPane: View {
    var body: some View {
        Section("システム全体") {
            KeyboardShortcuts.Recorder("表示 / 非表示", name: .toggleTerminal)
        }
        Section {
            KeyboardShortcuts.Recorder("ピン留めの切り替え", name: .togglePin)
            KeyboardShortcuts.Recorder("新しいタブ", name: .newTab)
            KeyboardShortcuts.Recorder("タブを閉じる", name: .closeTab)
            KeyboardShortcuts.Recorder("次のタブ", name: .nextTab)
            KeyboardShortcuts.Recorder("前のタブ", name: .previousTab)
            KeyboardShortcuts.Recorder("ウィンドウを伸ばす", name: .growWindow)
            KeyboardShortcuts.Recorder("ウィンドウを縮める", name: .shrinkWindow)
            KeyboardShortcuts.Recorder("半透明の切り替え", name: .toggleTranslucent)
        } header: {
            Text("ターミナルが前面にあるとき")
        } footer: {
            Text("環境設定 (⌘,) と終了 (⌘Q) は固定です。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WindowPane: View {
    @AppStorage(SettingsKey.slideEdge) private var slideEdge = SlideEdge.top
    @AppStorage(SettingsKey.tabBarPosition) private var tabBarPosition = TabBarPosition.top
    @AppStorage(SettingsKey.heightRatio) private var heightRatio = Constants.defaultHeightRatio
    @AppStorage(SettingsKey.animationDuration) private var animationDuration = Constants.defaultAnimationDuration
    @AppStorage(SettingsKey.fade) private var fade = false
    @AppStorage(SettingsKey.translucent) private var translucent = false
    @AppStorage(SettingsKey.translucentOpacity) private var translucentOpacity = Constants.defaultTranslucentOpacity

    var body: some View {
        Section("位置と大きさ") {
            Picker("出てくる方向", selection: $slideEdge) {
                Text("上から").tag(SlideEdge.top)
                Text("下から").tag(SlideEdge.bottom)
            }
            Picker("タブの位置", selection: $tabBarPosition) {
                Text("上").tag(TabBarPosition.top)
                Text("下").tag(TabBarPosition.bottom)
                Text("出てくる方向に合わせる").tag(TabBarPosition.followSlideEdge)
            }
            LabeledContent("縦幅: \(Int((heightRatio * 100).rounded()))%") {
                Slider(value: $heightRatio, in: Constants.heightRatioRange, step: Constants.resizeStep)
            }
        }
        Section("アニメーション") {
            LabeledContent("速さ: \(String(format: "%.2f", animationDuration)) 秒") {
                Slider(value: $animationDuration, in: Constants.animationDurationRange, step: 0.05)
            }
            Toggle("フェードを入れる", isOn: $fade)
        }
        Section("背景") {
            Toggle("半透明にする", isOn: $translucent)
            LabeledContent("不透明度: \(Int((translucentOpacity * 100).rounded()))%") {
                Slider(value: $translucentOpacity, in: Constants.translucentOpacityRange, step: 0.05)
            }
            .disabled(!translucent)
        }
    }
}

private struct DisplayPane: View {
    @AppStorage(SettingsKey.displayMode) private var displayMode = DisplayMode.active
    @AppStorage(SettingsKey.specificDisplayID) private var specificDisplayID = ""
    /// Empty means "not chosen yet": the app asks the first time the display is missing.
    @AppStorage(SettingsKey.fallbackDisplay) private var fallbackDisplay = ""

    var body: some View {
        Section {
            Picker("表示するディスプレイ", selection: $displayMode) {
                Text("メインディスプレイ").tag(DisplayMode.main)
                Text("アクティブなディスプレイ").tag(DisplayMode.active)
                Text("指定したディスプレイ").tag(DisplayMode.specific)
            }
            if displayMode == .specific {
                Picker("指定するディスプレイ", selection: $specificDisplayID) {
                    Text("未選択").tag("")
                    ForEach(Self.connectedDisplays, id: \.id) { display in
                        Text(display.name).tag(display.id)
                    }
                    if !specificDisplayID.isEmpty, !Self.connectedDisplays.contains(where: { $0.id == specificDisplayID }) {
                        Text("接続されていないディスプレイ").tag(specificDisplayID)
                    }
                }
                Picker("外れたときの表示先", selection: $fallbackDisplay) {
                    Text("未設定 (次回に確認する)").tag("")
                    Text("メインディスプレイ").tag(FallbackDisplay.main.rawValue)
                    Text("アクティブなディスプレイ").tag(FallbackDisplay.active.rawValue)
                }
            }
        }
    }

    private static var connectedDisplays: [(id: String, name: String)] {
        NSScreen.screens.compactMap { screen in
            screen.displayUUID.map { ($0, screen.localizedName) }
        }
    }
}

private struct FontPane: View {
    @AppStorage(SettingsKey.fontFamily) private var fontFamily = ""
    @AppStorage(SettingsKey.fontSize) private var fontSize = Constants.defaultFontSize

    var body: some View {
        Section {
            Picker("フォント", selection: $fontFamily) {
                Text("既定 (Ghostty 内蔵)").tag("")
                ForEach(Self.monospacedFamilies, id: \.self) { Text($0).tag($0) }
                if !fontFamily.isEmpty, !Self.monospacedFamilies.contains(fontFamily) {
                    Text("\(fontFamily) (見つかりません)").tag(fontFamily)
                }
            }
            Stepper("大きさ: \(fontSize.formatted()) pt", value: $fontSize, in: Constants.fontSizeRange, step: 1)
        } footer: {
            Text("文字を大きく・小さくするキーで変えたタブは、そのタブで変えた大きさのままになります。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("ターミナルが前面にあるときのキー") {
            KeyboardShortcuts.Recorder("文字を大きくする", name: .increaseFontSize)
            KeyboardShortcuts.Recorder("文字を小さくする", name: .decreaseFontSize)
        }
    }

    /// Installed families whose regular face is fixed-pitch, the only ones a terminal grid can use.
    private static let monospacedFamilies: [String] = NSFontManager.shared.availableFontFamilies.filter { family in
        guard let name = NSFontManager.shared.availableMembers(ofFontFamily: family)?.first?.first as? String else {
            return false
        }
        return NSFont(name: name, size: 12)?.isFixedPitch ?? false
    }
}

private struct TerminalPane: View {
    @AppStorage(SettingsKey.scrollbackLines) private var scrollbackLines = Constants.defaultScrollbackLines
    @AppStorage(SettingsKey.copyOnSelect) private var copyOnSelect = false

    var body: some View {
        Section {
            TextField("スクロールバックの保持行数", value: $scrollbackLines, format: .number)
            Toggle("選択しただけでコピーする", isOn: $copyOnSelect)
        }
    }
}

private struct NotificationsPane: View {
    @AppStorage(SettingsKey.notifyMinSeconds) private var notifyMinSeconds = Constants.defaultNotifyMinSeconds
    @AppStorage(SettingsKey.notifyResult) private var notifyResult = NotifyResult.always

    var body: some View {
        Section {
            Stepper("通知する最短の実行時間: \(notifyMinSeconds) 秒", value: $notifyMinSeconds, in: Constants.notifyMinSecondsRange)
            Picker("通知する結果", selection: $notifyResult) {
                Text("常に").tag(NotifyResult.always)
                Text("失敗時のみ").tag(NotifyResult.failureOnly)
            }
        } footer: {
            Text("ターミナルが隠れている間に終わったコマンドだけを通知します。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
