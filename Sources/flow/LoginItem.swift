import Cocoa
import ServiceManagement

/// Launch at login. An app bundle registers with macOS (System Settings › General › Login Items);
/// a bare binary gets a LaunchAgent, which also restarts it after a crash.
enum LoginItem {
    static let label = "dev.flow.agent"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var isBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static var isEnabled: Bool {
        if FileManager.default.fileExists(atPath: plistURL.path) { return true }
        return isBundle && SMAppService.mainApp.status == .enabled
    }

    /// Whether launchd started this process (so restarts should go through launchd, not pkill).
    static var runningUnderAgent: Bool { ProcessInfo.processInfo.environment["FLOW_LAUNCH_AGENT"] == "1" }

    @discardableResult
    static func set(_ on: Bool, forceAgent: Bool = false) -> String {
        if isBundle, !forceAgent {
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                return on ? "Flow will launch at login" : "Flow removed from login items"
            } catch {
                return "login item change failed: \(error.localizedDescription)"
            }
        }
        let uid = getuid()
        if on {
            let binary = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
            let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Flow.log").path
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [binary],
                "RunAtLoad": true,
                "KeepAlive": true,
                "ProcessType": "Interactive",
                "EnvironmentVariables": ["FLOW_LAUNCH_AGENT": "1"],
                "StandardOutPath": logPath,
                "StandardErrorPath": logPath,
            ]
            do {
                try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: plistURL)
            } catch {
                return "could not write \(plistURL.path): \(error.localizedDescription)"
            }
            _ = run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
            let out = run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistURL.path])
            return "Flow will launch at login via \(plistURL.lastPathComponent)\(out.isEmpty ? "" : " (\(out))")"
        } else {
            let out = run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
            try? FileManager.default.removeItem(at: plistURL)
            return "Flow removed from login items\(out.isEmpty ? "" : " (\(out))")"
        }
    }

    private static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = pipe
        do { try p.run() } catch { return error.localizedDescription }
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
