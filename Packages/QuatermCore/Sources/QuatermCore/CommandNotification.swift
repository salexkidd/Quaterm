/// Decides whether a finished command is worth a notification, and what it says.
public enum CommandNotification {
    public static func shouldNotify(
        windowVisible: Bool,
        exitCode: Int?,
        durationNanos: UInt64,
        minSeconds: Int,
        result: NotifyResult
    ) -> Bool {
        guard !windowVisible else { return false }
        guard durationNanos >= UInt64(minSeconds) * 1_000_000_000 else { return false }
        switch result {
        case .always: return true
        // An unknown exit code is not reported as a failure.
        case .failureOnly: return exitCode.map { $0 != 0 } ?? false
        }
    }

    public static func body(exitCode: Int?, durationNanos: UInt64) -> String {
        let seconds = Int(durationNanos / 1_000_000_000)
        return switch exitCode {
        case nil: Messages.commandFinishedUnknown(seconds: seconds)
        case 0: Messages.commandSucceeded(seconds: seconds)
        case let code?: Messages.commandFailed(exitCode: code, seconds: seconds)
        }
    }
}
