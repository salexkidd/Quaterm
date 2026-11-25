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
    public static let displayMissingInfo = "代わりにどこへ表示しますか？ 選んだ内容は環境設定で変更できます。キャンセルすると今回だけアクティブなディスプレイに表示し、次回もう一度たずねます。"
    public static let mainDisplay = "メインディスプレイ"
    public static let activeDisplay = "アクティブなディスプレイ"

    // Menus
    public static let menuToggle = "表示 / 非表示"
    public static let menuPreferences = "環境設定…"
    public static let menuQuit = "Quaterm を終了"
    public static let menuEdit = "編集"
    public static let menuOpenGhosttyConfig = "Ghostty の設定ファイルを開く…"

    // Ghostty config file
    public static let ghosttyConfigTemplate = """
        # Ghostty の設定ファイル。Quaterm はターミナルを表示するたびに読み直す。
        # 書き方: https://ghostty.org/docs/config
        # 文字の大きさ・不透明度・スクロールバック・選択でコピーは、Quaterm の環境設定が優先される。
        # フォントは、Quaterm の環境設定で「既定」を選んでいるときだけ、ここの font-family が効く。

        """
    public static let ghosttyConfigRejectedTitle = "Ghostty の設定ファイルを読み込めませんでした"
    public static func ghosttyConfigRejectedInfo(_ issue: String) -> String {
        "設定ファイルを使わずに動いています。直したあと、ターミナルを出し直すと読み込みます。\n\n\(issue)"
    }
    public static func ghosttyConfigUnreadable(_ path: String) -> String { "読めないファイル: \(path)" }
    public static func ghosttyConfigMissing(_ path: String) -> String { "config-file で指定したファイルがありません: \(path)" }
    public static let ghosttyConfigSkippedTitle = "Ghostty の設定ファイルの一部を読み飛ばしました"
    public static func ghosttyConfigSkippedInfo(_ lines: [String]) -> String {
        "次の行は Quaterm が使う libghostty で受け付けられないため、外して読み込みました。\n\n" + lines.joined(separator: "\n")
    }
    public static let ghosttyConfigOpenFailedTitle = "Ghostty の設定ファイルを開けませんでした"

    // Tabs
    public static let newTabTitle = "シェル"
    public static let closeTab = "タブを閉じる"
    public static let pinned = "ピン留め中"
    public static let unpinned = "ピン留めしていない"
}
