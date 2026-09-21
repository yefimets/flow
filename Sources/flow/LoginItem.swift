import Cocoa
import ServiceManagement

/// Launch on Start. An app bundle registers with macOS (System Settings › General › Login Items);
/// a bare binary, or a dev build asked for it, gets a LaunchAgent, which also restarts it after a crash.
enum LoginItem {
    static let label = "dev.flow.agent"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var isBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    static var hasAgent: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static var isEnabled: Bool {
        if hasAgent { return true }
        return isBundle && SMAppService.mainApp.status == .enabled
    }

    /// Whether launchd started this very process. The variable alone is not enough: a terminal Flow
    /// opened inherits it, and `flow login` typed there must behave as a shell command.
    static var runningUnderAgent: Bool {
        ProcessInfo.processInfo.environment["FLOW_LAUNCH_AGENT"] == "1" && getppid() == 1
    }

    /// On: a login item for the app bundle, a LaunchAgent for a bare binary or when one is already in use.
    /// Off: both are removed, whichever was installed, so the toggle always ends up off.
    @discardableResult
    static func set(_ on: Bool, forceAgent: Bool = false) -> String {
        let uid = getuid()
        if !on {
            var notes: [String] = []
            if hasAgent {
                // Unloading the agent stops its process. From inside that process, only drop the plist:
                // Flow keeps running now and simply does not come back at the next start.
                if !runningUnderAgent {
                    let out = run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
                    if !out.isEmpty { notes.append(out) }
                }
                try? FileManager.default.removeItem(at: plistURL)
            }
            if isBundle, [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) {
                do { try SMAppService.mainApp.unregister() } catch { notes.append(error.localizedDescription) }
            }
            return "Flow will not launch on start" + (notes.isEmpty ? "" : " (\(notes.joined(separator: "; ")))")
        }
        if isBundle, !forceAgent, !hasAgent, !runningUnderAgent {
            do {
                try SMAppService.mainApp.register()
                return "Flow will launch on start"
            } catch {
                return "login item change failed: \(error.localizedDescription)"
            }
        }
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Flow.log").path
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binary],
            "RunAtLoad": true,
            // Restart after a crash only. A clean exit (Quit Flow, ctrl+alt+q, flow cmd quit) stays quit.
            "KeepAlive": ["SuccessfulExit": false],
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
        // Re-bootstrapping from inside the running agent would kill this very process; the new plist
        // takes effect at the next start. From a shell, load it now.
        if runningUnderAgent { return "Flow will launch on start via \(plistURL.lastPathComponent)" }
        _ = run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
        let out = run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistURL.path])
        return "Flow will launch on start via \(plistURL.lastPathComponent)\(out.isEmpty ? "" : " (\(out))")"
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
