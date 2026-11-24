import AppKit
import KeyboardShortcuts
import QuatermCore
import SwiftUI

struct PreferencesView: View {
    @AppStorage(SettingsKey.showInDock) private var showInDock = true
    @AppStorage(SettingsKey.confirmQuit) private var confirmQuit = true
    @AppStorage(SettingsKey.slideEdge) private var slideEdge = SlideEdge.top
    @AppStorage(SettingsKey.heightRatio) private var heightRatio = Constants.defaultHeightRatio
    @AppStorage(SettingsKey.animationDuration) private var animationDuration = Constants.defaultAnimationDuration
    @AppStorage(SettingsKey.fade) private var fade = false
    @AppStorage(SettingsKey.displayMode) private var displayMode = DisplayMode.active
    @AppStorage(SettingsKey.specificDisplayID) private var specificDisplayID = ""
    /// Empty means "not chosen yet": the app asks the first time the display is missing.
    @AppStorage(SettingsKey.fallbackDisplay) private var fallbackDisplay = ""
    @AppStorage(SettingsKey.scrollbackLines) private var scrollbackLines = Constants.defaultScrollbackLines
    @AppStorage(SettingsKey.copyOnSelect) private var copyOnSelect = false
    @AppStorage(SettingsKey.notifyMinSeconds) private var notifyMinSeconds = Constants.defaultNotifyMinSeconds
    @AppStorage(SettingsKey.notifyResult) private var notifyResult = NotifyResult.always

    var body: some View {
        Form {
            Section("一般") {
                Toggle("Dock にアイコンを表示する", isOn: $showInDock)
                Toggle("終了時に確認する", isOn: $confirmQuit)
            }

            Section("キーボードショートカット") {
                KeyboardShortcuts.Recorder("表示 / 非表示 (システム全体)", name: .toggleTerminal)
                KeyboardShortcuts.Recorder("ピン留めの切り替え", name: .togglePin)
                KeyboardShortcuts.Recorder("新しいタブ", name: .newTab)
                KeyboardShortcuts.Recorder("タブを閉じる", name: .closeTab)
                KeyboardShortcuts.Recorder("ウィンドウを伸ばす", name: .growWindow)
                KeyboardShortcuts.Recorder("ウィンドウを縮める", name: .shrinkWindow)
                Text("「表示 / 非表示」以外は、ターミナルが前面にあるときだけ効きます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("ウィンドウ") {
                Picker("出てくる方向", selection: $slideEdge) {
                    Text("上から").tag(SlideEdge.top)
                    Text("下から").tag(SlideEdge.bottom)
                }
                LabeledContent("縦幅: \(Int((heightRatio * 100).rounded()))%") {
                    Slider(value: $heightRatio, in: Constants.heightRatioRange, step: Constants.resizeStep)
                }
                LabeledContent("アニメーション: \(String(format: "%.2f", animationDuration)) 秒") {
                    Slider(value: $animationDuration, in: Constants.animationDurationRange, step: 0.05)
                }
                Toggle("フェードを入れる", isOn: $fade)
            }

            Section("ディスプレイ") {
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

            Section("ターミナル") {
                TextField("スクロールバックの保持行数", value: $scrollbackLines, format: .number)
                Toggle("選択しただけでコピーする", isOn: $copyOnSelect)
            }

            Section("通知") {
                Stepper("通知する最短の実行時間: \(notifyMinSeconds) 秒", value: $notifyMinSeconds, in: Constants.notifyMinSecondsRange)
                Picker("通知する結果", selection: $notifyResult) {
                    Text("常に").tag(NotifyResult.always)
                    Text("失敗時のみ").tag(NotifyResult.failureOnly)
                }
                Text("ターミナルが隠れている間に終わったコマンドだけを通知します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static var connectedDisplays: [(id: String, name: String)] {
        NSScreen.screens.compactMap { screen in
            screen.displayUUID.map { ($0, screen.localizedName) }
        }
    }
}
