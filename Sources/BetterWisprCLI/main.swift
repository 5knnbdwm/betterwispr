import BetterWisprCore
import Foundation

enum CLIError: LocalizedError {
    case usage(String)
    var errorDescription: String? {
        switch self { case .usage(let message): message }
    }
}

@MainActor
func run() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.isEmpty || arguments == ["--help"] {
        print("""
        BetterWisprCLI: local speech recognition

          --list-models
          --download-model MODEL_ID
          --download-phrase-booster
          --download-speaker-detection
          --transcribe-file PATH [--model MODEL_ID] [--language en] [--vocabulary "Term,Other term"]
          --live-file PATH [--model MODEL_ID] [--language en]
            Feeds the file through the Parakeet live preview in real time, printing each confirmed | provisional
            update with its pass latency, then the batch transcription of the same file.
          --meeting PATH [--model MODEL_ID] [--language en] [--vocabulary "Term,Other term"] [--notes OUT.md] [--notes-model OLLAMA_MODEL]
            Plays the file through the meeting chunker as call audio, transcribes each chunk as meetings do and
            prints one JSON segment per line. Speaker detection labels voices when it is installed (macOS 15).
            --notes writes the meeting with notes from Apple Intelligence or the named Ollama model. With --notes,
            PATH may instead be a .jsonl file of segments from an earlier run, which skips transcription.
          --bench MANIFEST.jsonl [--model MODEL_ID] [--language auto|en] [--vocabulary "Term,Other term"] [--cleanup light|medium] [--notes-model OLLAMA_MODEL]
            Each manifest line is {"id", "language", "audio", "reference"}. Prints one JSON line per clip
            with the hypothesis and recognition seconds. Without --language, each clip uses its own language.
            --cleanup adds the app's cleanup of English text; medium edits with Apple's on-device model
            or the named Ollama model.

        Default model: parakeet-v3. Downloads only run with --download-model, --download-phrase-booster
        or --download-speaker-detection.
        Audio transcription loads existing local assets and never downloads them.
        """)
        return
    }
    if arguments == ["--list-models"] {
        for model in SpeechModel.catalog {
            print("\(model.id)\t\(model.name)\t\(model.sizeLabel)")
        }
        return
    }
    if arguments == ["--download-phrase-booster"] {
        try await ParakeetProvider.installPhraseBooster()
        print("Installed the Parakeet phrase booster at \(ParakeetProvider.phraseBoosterDirectory.path).")
        return
    }
    if arguments == ["--download-speaker-detection"] {
        try await SpeakerDetection.install()
        print("Installed speaker detection at \(SpeakerDetection.directory.path).")
        return
    }
    var options: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let option = arguments[index]
        guard ["--download-model", "--transcribe-file", "--live-file", "--bench", "--meeting", "--notes", "--model", "--language", "--vocabulary", "--cleanup", "--notes-model"].contains(option),
              index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--"), options[option] == nil else {
            throw CLIError.usage("Invalid or repeated argument: \(option). Run --help for usage.")
        }
        options[option] = arguments[index + 1]
        index += 2
    }
    guard options["--download-model"] != nil || options["--transcribe-file"] != nil || options["--live-file"] != nil || options["--bench"] != nil || options["--meeting"] != nil else {
        throw CLIError.usage("Choose --download-model, --transcribe-file, --live-file, --bench or --meeting.")
    }
    if let downloadID = options["--download-model"], let modelID = options["--model"], downloadID != modelID {
        throw CLIError.usage("Download and transcription must select the same model.")
    }
    let modelID = options["--model"] ?? options["--download-model"] ?? "parakeet-v3"
    guard let model = SpeechModel.catalog.first(where: { $0.id == modelID }) else {
        throw CLIError.usage("Unknown model: \(modelID). Run --list-models.")
    }
    let provider: any SpeechProvider
    switch model.engine {
    case .apple: throw CLIError.usage("Apple speech requires permissions granted through the macOS app. Select a Parakeet or Whisper model in the CLI.")
    case .whisperKit: provider = WhisperKitProvider()
    case .parakeet: provider = ParakeetProvider()
    case .api: throw CLIError.usage("Configure API connections in the macOS app. The CLI uses local models only.")
    }
    let clock = ContinuousClock()
    let started = clock.now
    if options["--download-model"] != nil {
        provider.onProgress = { FileHandle.standardError.write(Data("\rInstalling \(model.name): \(Int($0 * 100))%".utf8)) }
    }
    try await provider.prepare(model: model, download: options["--download-model"] != nil)
    FileHandle.standardError.write(Data("Prepared \(model.name) in \(started.duration(to: clock.now)).\n".utf8))
    let vocabulary = options["--vocabulary"].map { $0.split(separator: ",").map(String.init) } ?? []
    if let path = options["--bench"] {
        guard let cleanup = CleanupLevel(rawValue: options["--cleanup"] ?? "none") else {
            throw CLIError.usage("--cleanup must be light or medium.")
        }
        var settings = AppSettings()
        settings.cleanup = cleanup
        settings.notesModel = options["--notes-model"]
        try await bench(manifest: URL(fileURLWithPath: (path as NSString).expandingTildeInPath), provider: provider,
                        language: options["--language"], vocabulary: vocabulary, settings: settings)
    } else if let path = options["--meeting"] {
        var settings = AppSettings()
        settings.notesModel = options["--notes-model"]
        try await meeting(URL(fileURLWithPath: (path as NSString).expandingTildeInPath), provider: provider,
                          language: options["--language"].flatMap { $0 == "auto" ? nil : $0 }, vocabulary: vocabulary,
                          notes: options["--notes"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }, settings: settings)
    } else if let path = options["--live-file"] {
        guard let parakeet = provider as? ParakeetProvider else { throw CLIError.usage("--live-file needs a Parakeet model.") }
        try await live(URL(fileURLWithPath: (path as NSString).expandingTildeInPath), provider: parakeet,
                       language: options["--language"].flatMap { $0 == "auto" ? nil : $0 })
    } else if let path = options["--transcribe-file"] {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let language = options["--language"].flatMap { $0 == "auto" ? nil : $0 }
        let transcript = try await provider.transcribe(audioURL: url, language: language, vocabulary: vocabulary)
        print(transcript)
        FileHandle.standardError.write(Data("Completed in \(started.duration(to: clock.now)).\n".utf8))
    } else {
        print("\nInstalled \(model.name). Future transcription runs locally.")
    }
}

struct BenchClip: Codable {
    let id: String
    let language: String
    let audio: String
    let reference: String
}

struct BenchResult: Codable {
    let id: String
    let language: String
    let reference: String
    let hypothesis: String
    let seconds: Double
    var cleaned: String?
    var cleanupSeconds: Double?
}

/// Transcribes call audio chunk by chunk as a meeting does, then labels voices and optionally writes notes.
@MainActor
func meeting(_ url: URL, provider: any SpeechProvider, language: String?, vocabulary: [String], notes: URL?, settings: AppSettings) async throws {
    if url.pathExtension == "jsonl" {
        guard let notes else { throw CLIError.usage("Pass --notes OUT.md to write notes from saved segments.") }
        let segments = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).map { try JSONDecoder().decode(MeetingSegment.self, from: Data($0.utf8)) }
        return try await write(notes: notes, for: segments, language: language, settings: settings)
    }
    let voices = SpeakerDetection.isReady ? try SpeakerRecording() : nil
    defer { voices?.discard() }
    if voices == nil { FileHandle.standardError.write(Data("Speaker detection isn’t installed, so voices stay unlabeled.\n".utf8)) }
    var segments: [MeetingSegment] = []
    let chunks = try MeetingRecorder.chunks(of: url, speaker: .them)
    defer { for chunk in chunks { try? FileManager.default.removeItem(at: chunk.url) } }
    func segment(of audio: URL, start: TimeInterval, duration: TimeInterval) async throws -> MeetingSegment? {
        let raw = try await provider.transcribe(audioURL: audio, language: language, vocabulary: vocabulary)
        let text = TranscriptCleaner.clean(raw, language: language)
        return text.isEmpty ? nil : MeetingSegment(speaker: .them, start: start, duration: duration, text: text, rawText: raw)
    }
    for chunk in chunks where chunk.hasSpeech {
        do {
            guard let segment = try await segment(of: chunk.url, start: chunk.start, duration: chunk.duration) else { continue }
            segments.append(segment)
            try await voices?.append(chunk.url, for: segment.id)
        } catch {
            FileHandle.standardError.write(Data("Skipped \(Int(chunk.start)) s: \(error.localizedDescription)\n".utf8))
        }
    }
    if let voices {
        segments = try await SpeakerDetection.label(segments, voices: voices, transcribe: segment)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    for segment in segments { print(String(decoding: try encoder.encode(segment), as: UTF8.self)) }
    guard let notes else { return }
    try await write(notes: notes, for: segments, language: language, settings: settings)
}

@MainActor
func write(notes: URL, for segments: [MeetingSegment], language: String?, settings: AppSettings) async throws {
    var record = Meeting(segments: segments, modelName: "", language: language ?? "auto")
    let generated = try await MeetingNotesGenerator.generate(segments: segments, userNotes: "", settings: settings) { _, _ in }
    record.title = generated.title
    record.summary = generated.summary
    try record.markdown.write(to: notes, atomically: true, encoding: .utf8)
}

/// Transcribes every manifest clip with the prepared provider, one JSON line per clip on stdout.
@MainActor
func bench(manifest: URL, provider: any SpeechProvider, language: String?, vocabulary: [String], settings: AppSettings) async throws {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    let clock = ContinuousClock()
    for line in try String(contentsOf: manifest, encoding: .utf8).split(whereSeparator: \.isNewline) {
        let clip = try decoder.decode(BenchClip.self, from: Data(line.utf8))
        let spoken = (language ?? clip.language) == "auto" ? nil : language ?? clip.language
        let started = clock.now
        let hypothesis = try await provider.transcribe(audioURL: URL(fileURLWithPath: clip.audio), language: spoken, vocabulary: vocabulary)
        var result = BenchResult(id: clip.id, language: clip.language, reference: clip.reference, hypothesis: hypothesis,
                                 seconds: seconds(started.duration(to: clock.now)))
        if settings.cleanup != .none {
            let cleaning = clock.now
            var cleaned = TranscriptCleaner.clean(hypothesis, language: spoken)
            if settings.cleanup == .medium, TranscriptCleaner.isEnglish(cleaned, language: spoken) {
                cleaned = await TranscriptPolisher.polish(cleaned, settings: settings, vocabulary: vocabulary, context: nil) ?? cleaned
            }
            result.cleaned = cleaned
            result.cleanupSeconds = seconds(cleaning.duration(to: clock.now))
        }
        print(String(decoding: try encoder.encode(result), as: UTF8.self))
    }
}

/// Plays a file into the live preview at real-time pace in 100 ms chunks, then runs the batch pass on the same file.
@MainActor
func live(_ url: URL, provider: ParakeetProvider, language: String?) async throws {
    let samples = try ParakeetProvider.samples(of: url)
    let transcriber = LiveTranscriber()
    let clock = ContinuousClock()
    let started = clock.now
    transcriber.onUpdate = { [weak transcriber] transcript in
        let elapsed = String(format: "%5.1f", seconds(started.duration(to: clock.now)))
        let pass = String(format: "%.2f", seconds(transcriber?.lastPass ?? .zero))
        print("\(elapsed) s  pass \(pass) s  \(transcript.confirmed) | \(transcript.hypothesis)")
    }
    transcriber.beginBuffering()
    transcriber.start { try await provider.liveTranscribe($0, language: language) }
    let chunk = LiveTranscriber.sampleRate / 10
    for start in stride(from: 0, to: samples.count, by: chunk) {
        transcriber.append(Array(samples[start..<min(start + chunk, samples.count)]))
        try await Task.sleep(for: .milliseconds(100))
    }
    await transcriber.stop()
    print("live:  \(transcriber.transcript.confirmed) | \(transcriber.transcript.hypothesis)")
    print("batch: \(try await provider.transcribe(audioURL: url, language: language, vocabulary: []))")
}

func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

do {
    try await run()
} catch {
    FileHandle.standardError.write(Data("BetterWispr: \(error.localizedDescription)\n".utf8))
    exit(1)
}
