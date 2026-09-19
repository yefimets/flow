import CWhisper
import Foundation

/// On-device speech to text with whisper.cpp. The model file is fetched once into
/// ~/Library/Application Support/Flow and kept there.
final class WhisperTranscriber {
    static let shared = WhisperTranscriber()

    private var context: OpaquePointer?
    private var loadedModel = ""
    private var downloading = false

    static func modelURL(_ name: String) -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Flow")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ggml-\(name).bin")
    }

    static func remoteURL(_ name: String) -> URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(name).bin")!
    }

    var isReady: Bool { context != nil }

    /// Makes sure the model file exists, downloading it when needed. `progress` gets 0…1.
    func ensureModel(_ name: String, progress: @escaping (Double) -> Void) async throws -> URL {
        let url = Self.modelURL(name)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard !downloading else { throw NSError(domain: "Whisper", code: 2, userInfo: [NSLocalizedDescriptionKey: "model download already in progress"]) }
        downloading = true
        defer { downloading = false }
        log("whisper: downloading model \(name) to \(url.path)")
        let (tmp, response) = try await URLSession.shared.download(from: Self.remoteURL(name), delegate: nil)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Whisper", code: 3, userInfo: [NSLocalizedDescriptionKey: "model download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))"])
        }
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: tmp, to: url)
        progress(1)
        log("whisper: model \(name) ready")
        return url
    }

    func load(model name: String) throws {
        if context != nil, loadedModel == name { return }
        if let c = context { whisper_free(c); context = nil }
        let path = Self.modelURL(name).path
        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true
        guard let c = whisper_init_from_file_with_params(path, params) else {
            throw NSError(domain: "Whisper", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not load model at \(path)"])
        }
        context = c
        loadedModel = name
        log("whisper: loaded \(name)")
    }

    /// Transcribes 16 kHz mono float samples. Language is detected automatically.
    func transcribe(samples: [Float], language: String? = nil) throws -> String {
        guard let ctx = context else { throw NSError(domain: "Whisper", code: 4, userInfo: [NSLocalizedDescriptionKey: "model not loaded"]) }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.single_segment = false
        params.no_timestamps = true
        params.n_threads = Int32(max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        params.detect_language = false
        let lang = language ?? "auto"
        var text = ""
        try lang.withCString { cLang in
            params.language = cLang
            let rc = samples.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
            guard rc == 0 else { throw NSError(domain: "Whisper", code: 5, userInfo: [NSLocalizedDescriptionKey: "whisper_full failed (\(rc))"]) }
            let n = whisper_full_n_segments(ctx)
            for i in 0..<n {
                if let seg = whisper_full_get_segment_text(ctx, i) { text += String(cString: seg) }
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 16-bit PCM WAV (as recorded) to float samples.
    static func samples(fromWAV data: Data) -> [Float] {
        guard data.count > 44 else { return [] }
        // Find the "data" chunk rather than assuming a 44-byte header.
        var offset = 12
        var dataStart = 44
        var dataLength = data.count - 44
        while offset + 8 <= data.count {
            let id = String(bytes: data[offset..<offset + 4], encoding: .ascii) ?? ""
            let size = Int(data[offset + 4]) | Int(data[offset + 5]) << 8 | Int(data[offset + 6]) << 16 | Int(data[offset + 7]) << 24
            if id == "data" { dataStart = offset + 8; dataLength = min(size, data.count - dataStart); break }
            offset += 8 + size + (size & 1)
        }
        let count = dataLength / 2
        var out = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: dataStart)
            for i in 0..<count {
                let lo = Int16(base.load(fromByteOffset: i * 2, as: UInt8.self))
                let hi = Int16(base.load(fromByteOffset: i * 2 + 1, as: UInt8.self))
                let sample = Int16(bitPattern: UInt16(truncatingIfNeeded: (Int(hi) << 8) | Int(lo)))
                out[i] = Float(sample) / 32768
            }
        }
        return out
    }
}
