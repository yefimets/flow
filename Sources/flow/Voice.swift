import AVFoundation
import Cocoa
import SwiftUI

// MARK: - Configuration

/// Settings for the voice agent, "Jev". The API key never goes into logs or the repository:
/// it is read from the config file or the OPENROUTER_API_KEY environment variable.
struct VoiceConfig {
    var apiKey: String = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
    /// "whisper" runs on this Mac (default); "openrouter" sends the audio to `transcribeModel`.
    var transcriber = "whisper"
    /// whisper.cpp model size: tiny, base, small, medium, large-v3-turbo. Larger is slower and better.
    var whisperModel = "base"
    /// Spoken language for whisper, or "auto".
    var language = "auto"
    var transcribeModel = "google/gemini-2.5-flash"
    var agentModel = "google/gemini-2.5-flash"
    var speak = false
    var name = "Jev"

    var enabled: Bool { !apiKey.isEmpty }

    static func load(from obj: [String: Any]) -> VoiceConfig {
        var v = VoiceConfig()
        guard let d = obj["voice"] as? [String: Any] else { return v }
        if let k = d["apiKey"] as? String, !k.isEmpty { v.apiKey = k }
        v.transcriber = d["transcriber"] as? String ?? v.transcriber
        v.whisperModel = d["whisperModel"] as? String ?? v.whisperModel
        v.language = d["language"] as? String ?? v.language
        v.transcribeModel = d["transcribeModel"] as? String ?? v.transcribeModel
        v.agentModel = d["agentModel"] as? String ?? v.agentModel
        v.speak = d["speak"] as? Bool ?? v.speak
        v.name = d["name"] as? String ?? v.name
        return v
    }
}

// MARK: - Typed tools

/// Everything Jev is allowed to do, as a closed set of typed commands. The model's JSON is decoded
/// into these; anything that does not decode is refused, so the agent can never run arbitrary code.
enum JevTool {
    case switchFlow(Int)
    case moveWindowToFlow(Int)
    case newFlow
    case removeFlow
    case focus(Direction)
    case swap(Direction)
    case toggleFloat
    case toggleFullscreen
    case closeWindow
    case openBrowser
    case openTerminal
    case openApp(String)
    case openURL(String)
    case screenshotFlow(Int?)
    case say(String)
    case webSearch(String)
    case createNote(title: String, body: String)
    case typeText(String)
    case pressKey(String)

    struct Call { let id: String; let name: String; let arguments: [String: Any] }

    init(call: Call) throws {
        func int(_ k: String) throws -> Int {
            if let n = call.arguments[k] as? Int { return n }
            if let d = call.arguments[k] as? Double { return Int(d) }
            if let s = call.arguments[k] as? String, let n = Int(s) { return n }
            throw DecodingError.valueNotFound(Int.self, .init(codingPath: [], debugDescription: "missing \(k)"))
        }
        func str(_ k: String) throws -> String {
            guard let s = call.arguments[k] as? String, !s.isEmpty else {
                throw DecodingError.valueNotFound(String.self, .init(codingPath: [], debugDescription: "missing \(k)"))
            }
            return s
        }
        func dir() throws -> Direction {
            switch try str("direction").lowercased() {
            case "left": return .left
            case "right": return .right
            case "up": return .up
            case "down": return .down
            default: throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad direction"))
            }
        }
        switch call.name {
        case "switch_flow": self = .switchFlow(try int("flow"))
        case "move_window_to_flow": self = .moveWindowToFlow(try int("flow"))
        case "new_flow": self = .newFlow
        case "remove_flow": self = .removeFlow
        case "focus": self = .focus(try dir())
        case "swap": self = .swap(try dir())
        case "toggle_float": self = .toggleFloat
        case "toggle_fullscreen": self = .toggleFullscreen
        case "close_window": self = .closeWindow
        case "open_browser": self = .openBrowser
        case "open_terminal": self = .openTerminal
        case "open_app": self = .openApp(try str("name"))
        case "open_url": self = .openURL(try str("url"))
        case "screenshot_flow": self = .screenshotFlow(call.arguments["flow"] as? Int)
        case "say": self = .say(try str("text"))
        case "web_search": self = .webSearch(try str("query"))
        case "create_note": self = .createNote(title: try str("title"), body: (call.arguments["body"] as? String) ?? "")
        case "type_text": self = .typeText(try str("text"))
        case "press_key":
            let key = try str("key").lowercased()
            guard ["return", "escape", "tab", "find", "address_bar", "select_all", "copy", "paste", "new_tab", "save"].contains(key) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unknown key \(key)"))
            }
            self = .pressKey(key)
        default: throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unknown tool \(call.name)"))
        }
    }

    /// The same set, described to the model as OpenAI-style function tools.
    static let schema: [[String: Any]] = {
        func tool(_ name: String, _ description: String, _ props: [String: Any] = [:], required: [String] = []) -> [String: Any] {
            ["type": "function", "function": ["name": name, "description": description,
                                              "parameters": ["type": "object", "properties": props, "required": required]]]
        }
        let flow: [String: Any] = ["type": "integer", "minimum": 1, "maximum": 9, "description": "Flow number 1-9"]
        let direction: [String: Any] = ["type": "string", "enum": ["left", "right", "up", "down"]]
        return [
            tool("switch_flow", "Switch to a flow (workspace). Creates it if missing.", ["flow": flow], required: ["flow"]),
            tool("move_window_to_flow", "Move the focused window to a flow and follow it.", ["flow": flow], required: ["flow"]),
            tool("new_flow", "Create a new empty flow and switch to it."),
            tool("remove_flow", "Remove the current flow and close its windows."),
            tool("focus", "Focus the neighbouring window in a direction.", ["direction": direction], required: ["direction"]),
            tool("swap", "Swap the focused window with its neighbour in a direction.", ["direction": direction], required: ["direction"]),
            tool("toggle_float", "Toggle the focused window between floating and tiled."),
            tool("toggle_fullscreen", "Toggle fullscreen for the focused window."),
            tool("close_window", "Close the focused window."),
            tool("open_browser", "Open a new browser window in the current flow."),
            tool("open_terminal", "Open a new terminal window in the current flow."),
            tool("open_app", "Launch or bring forward a macOS application by name, e.g. Notes, Telegram, Messages.",
                 ["name": ["type": "string"]], required: ["name"]),
            tool("open_url", "Open a URL in the default browser.", ["url": ["type": "string"]], required: ["url"]),
            tool("screenshot_flow", "Capture every window of a flow to PNG files (current flow if omitted).", ["flow": flow]),
            tool("say", "Tell the user something short. Use it to confirm what you did or to ask for clarification.",
                 ["text": ["type": "string"]], required: ["text"]),
            tool("web_search", "Open Chrome in the current flow with a Google search for the query.",
                 ["query": ["type": "string"]], required: ["query"]),
            tool("create_note", "Create a note in Apple Notes with a title and body text.",
                 ["title": ["type": "string"], "body": ["type": "string"]], required: ["title"]),
            tool("type_text", "Type text into whatever has keyboard focus, as if on the keyboard. Focus the right app first.",
                 ["text": ["type": "string"]], required: ["text"]),
            tool("press_key", "Press a key in the focused app.",
                 ["key": ["type": "string", "enum": ["return", "escape", "tab", "find", "address_bar", "select_all", "copy", "paste", "new_tab", "save"]]],
                 required: ["key"]),
        ]
    }()
}

// MARK: - OpenRouter client

enum OpenRouter {
    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    struct Reply {
        var text: String
        var calls: [JevTool.Call]
        /// The assistant message as returned, replayed into the conversation before tool results.
        var assistantMessage: [String: Any]
    }

    static func chat(apiKey: String, model: String, messages: [[String: Any]], tools: [[String: Any]]? = nil) async throws -> Reply {
        var body: [String: Any] = ["model": model, "messages": messages]
        if let tools { body["tools"] = tools; body["tool_choice"] = "auto" }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://github.com/yefimets/flow", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Flow", forHTTPHeaderField: "X-Title")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OpenRouter", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: String(text.prefix(300))])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else {
            throw NSError(domain: "OpenRouter", code: 1, userInfo: [NSLocalizedDescriptionKey: "unexpected response shape"])
        }
        let text = (message["content"] as? String) ?? ""
        var calls: [JevTool.Call] = []
        for (i, tc) in (message["tool_calls"] as? [[String: Any]] ?? []).enumerated() {
            guard let fn = tc["function"] as? [String: Any], let name = fn["name"] as? String else { continue }
            var args: [String: Any] = [:]
            if let raw = fn["arguments"] as? String, let d = raw.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { args = parsed }
            else if let dict = fn["arguments"] as? [String: Any] { args = dict }
            calls.append(.init(id: tc["id"] as? String ?? "call_\(i)", name: name, arguments: args))
        }
        var assistant: [String: Any] = ["role": "assistant", "content": text]
        if let tcs = message["tool_calls"] { assistant["tool_calls"] = tcs }
        return Reply(text: text, calls: calls, assistantMessage: assistant)
    }

    /// Speech to text: the audio goes as an input_audio part to a model that accepts audio.
    static func transcribe(apiKey: String, model: String, wav: Data) async throws -> String {
        let messages: [[String: Any]] = [
            ["role": "system", "content": "You are a transcription engine. Return only the exact words spoken, in the language spoken, with no commentary. If there is no speech, return an empty string."],
            ["role": "user", "content": [
                ["type": "text", "text": "Transcribe this audio."],
                ["type": "input_audio", "input_audio": ["data": wav.base64EncodedString(), "format": "wav"]],
            ]],
        ]
        return try await chat(apiKey: apiKey, model: model, messages: messages).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Recorder

final class Recorder {
    private var recorder: AVAudioRecorder?
    private(set) var url: URL?

    func start() throws {
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("flow-voice-\(Int(Date().timeIntervalSince1970)).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let r = try AVAudioRecorder(url: file, settings: settings)
        r.prepareToRecord()
        r.record()
        recorder = r
        url = file
    }

    /// Stops and returns the WAV bytes, or nil for a recording too short to contain speech.
    func stop() -> Data? {
        guard let r = recorder else { return nil }
        let seconds = r.currentTime
        r.stop()
        recorder = nil
        defer { if let url { try? FileManager.default.removeItem(at: url) } }
        guard seconds > 0.4, let url, let data = try? Data(contentsOf: url) else { return nil }
        return data
    }
}

// MARK: - HUD

final class VoiceHUD: ObservableObject {
    @Published var state = ""
    @Published var transcript = ""
    @Published var reply = ""
    private var window: KeyPanel?
    private var hideTimer: Timer?

    func show(state: String, transcript: String = "", reply: String = "") {
        self.state = state
        self.transcript = transcript
        self.reply = reply
        hideTimer?.invalidate()
        if window == nil {
            let w = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 120), styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.level = .floating
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            w.contentView = NSHostingView(rootView: VoiceHUDView(hud: self))
            window = w
        }
        if let screen = NSScreen.main, let window {
            let f = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.midX - 230, y: f.maxY - 140))
            window.orderFrontRegardless()
        }
    }

    func hide(after seconds: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.window?.orderOut(nil)
        }
    }
}

struct VoiceHUDView: View {
    @ObservedObject var hud: VoiceHUD
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: hud.state == "Listening…" ? "waveform" : "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                Text(hud.state).font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            if !hud.transcript.isEmpty {
                Text("“\(hud.transcript)”").font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !hud.reply.isEmpty {
                Text(hud.reply).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 460, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}

// MARK: - Controller

/// Hold ⌥ to talk. Release: transcribe, hand the text to Jev, run the typed tools it picks, speak the reply.
final class VoiceController {
    static let shared = VoiceController()
    var config = VoiceConfig()
    var execute: ((JevTool) -> Void)?
    var context: (() -> String)?

    private let recorder = Recorder()
    private let hud = VoiceHUD()
    private let synth = NSSpeechSynthesizer()
    private var recording = false

    func beginHold() {
        guard config.enabled, !recording else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, granted else { log("voice: microphone access denied"); return }
                do {
                    try self.recorder.start()
                    self.recording = true
                    self.hud.show(state: "Listening…")
                } catch {
                    log("voice: could not record: \(error.localizedDescription)")
                }
            }
        }
    }

    func endHold() {
        guard recording else { return }
        recording = false
        guard let wav = recorder.stop() else {
            hud.show(state: "Too short")
            hud.hide(after: 1)
            return
        }
        hud.show(state: "Transcribing…")
        Task { await process(wav: wav) }
    }

    /// A WAV file through the whole pipeline, for tests: `flow cmd voicefile clip.wav`.
    func handle(wavPath: String) {
        guard config.enabled else { log("voice: no OpenRouter API key configured"); return }
        guard let wav = try? Data(contentsOf: URL(fileURLWithPath: wavPath)) else { log("voice: cannot read \(wavPath)"); return }
        hud.show(state: "Transcribing…")
        Task { await process(wav: wav) }
    }

    /// Text straight to Jev, for scripts and tests: `flow cmd jev "switch to flow 2"`.
    func handle(text: String) {
        guard config.enabled else { log("voice: no OpenRouter API key configured"); return }
        hud.show(state: "\(config.name) is thinking…", transcript: text)
        Task { await ask(transcript: text) }
    }

    /// Loads the whisper model in the background at startup so the first command is not slow.
    func warmUp() {
        guard config.transcriber == "whisper" else { return }
        let name = config.whisperModel
        Task.detached(priority: .utility) {
            do {
                _ = try await WhisperTranscriber.shared.ensureModel(name) { _ in }
                try WhisperTranscriber.shared.load(model: name)
            } catch {
                log("whisper: not ready: \(error.localizedDescription)")
            }
        }
    }

    private func transcribe(wav: Data) async throws -> String {
        guard config.transcriber == "whisper" else {
            return try await OpenRouter.transcribe(apiKey: config.apiKey, model: config.transcribeModel, wav: wav)
        }
        let name = config.whisperModel
        if !FileManager.default.fileExists(atPath: WhisperTranscriber.modelURL(name).path) {
            await MainActor.run { hud.show(state: "Downloading speech model…") }
        }
        _ = try await WhisperTranscriber.shared.ensureModel(name) { _ in }
        try WhisperTranscriber.shared.load(model: name)
        let samples = WhisperTranscriber.samples(fromWAV: wav)
        let started = Date()
        let text = try WhisperTranscriber.shared.transcribe(samples: samples, language: config.language == "auto" ? nil : config.language)
        log("whisper: \(String(format: "%.1f", Double(samples.count) / 16000))s of audio in \(String(format: "%.2f", Date().timeIntervalSince(started)))s")
        return text
    }

    private func process(wav: Data) async {
        do {
            let text = try await transcribe(wav: wav)
            guard !text.isEmpty else {
                await MainActor.run { hud.show(state: "Heard nothing"); hud.hide(after: 1.5) }
                return
            }
            log("voice: heard \"\(text)\"")
            await MainActor.run { hud.show(state: "\(config.name) is thinking…", transcript: text) }
            await ask(transcript: text)
        } catch {
            log("voice: transcription failed: \(error.localizedDescription)")
            await MainActor.run { hud.show(state: "Transcription failed", reply: error.localizedDescription); hud.hide(after: 4) }
        }
    }

    private func ask(transcript: String) async {
        let system = """
        You are \(config.name), a voice assistant that operates the user's Mac through Flow, a tiling window manager \
        with numbered flows (workspaces). Do what the user asks by calling tools; call several when the request needs it. \
        For notes use create_note. For searching the web use web_search. type_text and press_key act on the focused app; \
        open_app first when you need a particular app to have focus, and wait for the tool result before typing. \
        Do the job silently: do not narrate or confirm. Use `say` only when you cannot proceed and need one \
        clarifying question, in the user's language. Never invent flow numbers the user did not mention.
        Current state:
        \(context?() ?? "")
        """
        var messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": transcript],
        ]
        do {
            var spoken = ""
            var ran = 0
            // Tool loop: run what the model asks for, feed the results back, let it continue, at most five rounds.
            for _ in 0..<5 {
                let reply = try await OpenRouter.chat(apiKey: config.apiKey, model: config.agentModel, messages: messages, tools: JevTool.schema)
                if reply.calls.isEmpty {
                    if !reply.text.isEmpty { spoken = reply.text }
                    break
                }
                messages.append(reply.assistantMessage)
                for call in reply.calls {
                    var result = "ok"
                    do {
                        let tool = try JevTool(call: call)
                        if case .say(let text) = tool {
                            spoken = text
                            result = "said"
                        } else {
                            log("jev: \(call.name) \(call.arguments)")
                            await MainActor.run { execute?(tool) }
                            ran += 1
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            result = "done. " + (await MainActor.run { context?() ?? "" })
                        }
                    } catch {
                        log("jev: refused \(call.name): \(error)")
                        result = "refused: \(error)"
                    }
                    messages.append(["role": "tool", "tool_call_id": call.id, "content": result])
                }
                if reply.calls.contains(where: { $0.name == "say" }) { break }
            }
            let message = spoken
            log("jev: \(message.isEmpty ? "done (\(ran) tool\(ran == 1 ? "" : "s"))" : message)")
            await MainActor.run {
                if message.isEmpty {
                    hud.hide(after: 0)
                } else {
                    // Only a question or a refusal reaches the user; a completed job just happens.
                    hud.show(state: config.name, transcript: transcript, reply: message)
                    hud.hide(after: 5)
                    if config.speak { synth.startSpeaking(message) }
                }
            }
        } catch {
            log("jev: request failed: \(error.localizedDescription)")
            await MainActor.run { hud.show(state: "\(config.name) failed", transcript: transcript, reply: error.localizedDescription); hud.hide(after: 5) }
        }
    }
}
