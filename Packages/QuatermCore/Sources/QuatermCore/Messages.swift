/// Every user-facing string in one place.
public enum Messages {
    public static let appName = "Quaterm"

    // Notifications
    public static func commandSucceeded(seconds: Int) -> String { "成功 (\(seconds) 秒)" }
    public static func commandFailed(exitCode: Int, seconds: Int) -> String { "失敗 (返り値 \(exitCode), \(seconds) 秒)" }
    public static func commandFinishedUnknown(seconds: Int) -> String { "終了 (\(seconds) 秒)" }

    // Quit confirmation
    public static let quitTitle = "Quaterm を終了しますか？"
    public static let quitInfo = "開いているタブのシェルはすべて終了します。"
    public static let quitButton = "終了"
    public static let cancelButton = "キャンセル"
    public static let dontAskAgain = "次回から表示しない"

    // Closing the last tab
    public static let closeLastTabTitle = "最後のタブを閉じますか？"
    public static let closeLastTabInfo = "シェルが終了し、ターミナルは隠れます。"
    public static let closeButton = "閉じる"

    // Missing display
    public static let displayMissingTitle = "指定したディスプレイが見つかりません"
    public static let displayMissingInfo = "代わりにどこへ表示しますか？ 選んだ内容は環境設定で変更できます。"
    public static let mainDisplay = "メインディスプレイ"
    public static let activeDisplay = "アクティブなディスプレイ"

    // Menus
    public static let menuToggle = "表示 / 非表示"
    public static let menuPreferences = "環境設定…"
    public static let menuQuit = "Quaterm を終了"
    public static let menuEdit = "編集"
    public static let preferencesTitle = "Quaterm 環境設定"

    // Tabs
    public static let newTabTitle = "シェル"
    public static let closeTab = "タブを閉じる"
    public static let pinned = "ピン留め中"
    public static let unpinned = "ピン留めしていない"
}
