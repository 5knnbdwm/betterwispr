@preconcurrency import AVFoundation
import Foundation
import SpeakerKit
import WhisperKit

/// Tells the voices on the other side of a call apart after a meeting, on this Mac.
public enum SpeakerDetection {
    private static let repo = "argmaxinc/speakerkit-coreml"
    private static let revision = "556fc52a13327837688f02289457cded017802e9"
    private static let segmenter = ModelInfo.segmenter(variant: "W32A32")
    private static let embedder = ModelInfo.embedder(variant: "W8A16")
    private static let models = [
        (info: segmenter, files: ["SpeakerSegmenter"]),
        (info: embedder, files: ["SpeakerEmbedderPreprocessor", "SpeakerEmbedder"]),
        (info: ModelInfo.plda(), files: ["PldaProjector"])
    ]

    public static var directory: URL {
        WhisperKitProvider.defaultModelsDirectory.appending(path: "models/\(repo)", directoryHint: .isDirectory)
    }

    public static func isInstalled(at directory: URL = directory) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: ".betterwispr-installed").path) && models.allSatisfy { model in
            model.files.allSatisfy { FileManager.default.fileExists(atPath: model.info.modelURL(baseURL: directory).appending(path: "\($0).mlmodelc").path) }
        }
    }

    /// Downloads and verifies the pinned models after an explicit installation action, then removes the FluidAudio speaker models they replace.
    public static func install(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let base = WhisperKitProvider.defaultModelsDirectory
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let downloader = ModelDownloader(config: ModelDownloadConfig(downloadBase: base.path, modelRepo: repo, revision: revision))
        do {
            _ = try await downloader.resolveRepo(patterns: models.map(\.info.downloadPattern), downloadBase: base, download: true) {
                progress?($0.fractionCompleted)
            }
        } catch {
            throw WhisperKitProvider.readableDownloadError(error)
        }
        try Task.checkCancellation()
        _ = try await installedDiarizer(from: directory)
        try Task.checkCancellation()
        try Data(revision.utf8).write(to: directory.appending(path: ".betterwispr-installed"), options: .atomic)
        let legacy = URL.applicationSupportDirectory.appending(path: "FluidAudio/Models/speaker-diarization", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: legacy.appending(path: ".betterwispr-installed").path) {
            try? FileManager.default.removeItem(at: legacy)
        }
    }

    static func installedDiarizer(from directory: URL) async throws -> SpeakerKitDiarizer {
        let diarizer = SpeakerKitDiarizer.pyannote(
            config: PyannoteConfig(modelFolder: directory.path, download: false, load: false, verbose: false),
            segmenterModelInfo: segmenter, embedderModelInfo: embedder)
        try await diarizer.loadModels()
        return diarizer
    }

    static func abandoningOnCancel<Value: Sendable>(_ work: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let (results, continuation) = AsyncThrowingStream<Value, any Error>.makeStream()
        Task {
            do {
                continuation.yield(try await work())
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        for try await result in results { return result }
        throw CancellationError()
    }

    /// Splits each segment into the voices heard in it, folding any stretch shorter than `shortest` seconds into a neighbour.
    static func voiceTurns(turns: [SpeakerSegment], placements: [SpeakerRecording.Placement], shortest: TimeInterval = 1) -> [UUID: [VoiceTurn]] {
        let turns = turns.compactMap { turn in
            turn.speaker.speakerId.map { VoiceTurn(voice: String($0), start: TimeInterval(turn.startTime), end: TimeInterval(turn.endTime)) }
        }.sorted { $0.start < $1.start }
        var result: [UUID: [VoiceTurn]] = [:]
        for placement in placements {
            var runs: [VoiceTurn] = []
            for turn in turns {
                let start = max(placement.start, turn.start, runs.last?.end ?? 0)
                let end = min(placement.end, turn.end)
                guard end > start else { continue }
                if runs.last?.voice == turn.voice { runs[runs.count - 1].end = end } else { runs.append(VoiceTurn(voice: turn.voice, start: start, end: end)) }
            }
            while runs.count > 1, let index = runs.indices.min(by: { runs[$0].length < runs[$1].length }), runs[index].length < shortest {
                let neighbour = index == 0 ? 1 : index == runs.count - 1 || runs[index - 1].length >= runs[index + 1].length ? index - 1 : index + 1
                runs[neighbour].start = min(runs[neighbour].start, runs[index].start)
                runs[neighbour].end = max(runs[neighbour].end, runs[index].end)
                runs.remove(at: index)
                runs = runs.reduce(into: []) { merged, run in
                    if merged.last?.voice == run.voice { merged[merged.count - 1].end = run.end } else { merged.append(run) }
                }
            }
            guard !runs.isEmpty else { continue }
            result[placement.segment] = runs.indices.map { index in
                let start = index == 0 ? placement.start : (runs[index - 1].end + runs[index].start) / 2
                let end = index == runs.count - 1 ? placement.end : (runs[index].end + runs[index + 1].start) / 2
                return VoiceTurn(voice: runs[index].voice, start: start - placement.start, end: end - placement.start)
            }
        }
        return result
    }

    /// Gives each Them segment its voice and transcribes a segment again in pieces when several voices speak in it.
    /// A segment keeps its text and takes its longest voice when a piece can't be transcribed. Voices are numbered 1, 2, 3 by first appearance.
    @MainActor
    public static func label(_ segments: [MeetingSegment], voices: SpeakerRecording,
                             transcribe: (_ audio: URL, _ start: TimeInterval, _ duration: TimeInterval) async throws -> MeetingSegment?) async throws -> [MeetingSegment] {
        try await label(segments, turns: voices.voiceTurns(), audio: { try await voices.audio(of: $0, from: $1.start, to: $1.end) }, transcribe: transcribe)
    }

    @MainActor
    static func label(_ segments: [MeetingSegment], turns: [UUID: [VoiceTurn]], audio: (UUID, VoiceTurn) async throws -> URL,
                      transcribe: (_ audio: URL, _ start: TimeInterval, _ duration: TimeInterval) async throws -> MeetingSegment?) async throws -> [MeetingSegment] {
        var labelled: [(segment: MeetingSegment, voice: String?)] = []
        for segment in segments {
            guard let pieces = turns[segment.id], let longest = pieces.max(by: { $0.length < $1.length }) else {
                labelled.append((segment, nil))
                continue
            }
            var split: [(segment: MeetingSegment, voice: String?)] = []
            for piece in pieces where pieces.count > 1 {
                try Task.checkCancellation()
                do {
                    let url = try await audio(segment.id, piece)
                    defer { try? FileManager.default.removeItem(at: url) }
                    if let transcribed = try await transcribe(url, segment.start + piece.start, piece.length) { split.append((transcribed, piece.voice)) }
                } catch {
                    split = []
                    break
                }
            }
            try Task.checkCancellation()
            labelled += split.isEmpty ? [(segment, longest.voice)] : split
        }
        var numbers: [String: Int] = [:]
        return labelled.map { segment, voice in
            var segment = segment
            if let voice {
                segment.participant = numbers[voice] ?? numbers.count + 1
                numbers[voice] = segment.participant
            }
            return segment
        }
    }
}

struct VoiceTurn: Equatable, Sendable {
    var voice: String
    var start: TimeInterval
    var end: TimeInterval

    var length: TimeInterval { end - start }
}

/// Collects the call audio behind each transcribed Them segment into one 16 kHz file, then finds who spoke each one.
public actor SpeakerRecording {
    struct Placement: Sendable {
        var segment: UUID
        var start: TimeInterval
        var end: TimeInterval
    }

    public nonisolated let url: URL
    private var file: AVAudioFile?
    private var placements: [Placement] = []
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!

    public init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "betterwispr-meeting-voices-\(UUID().uuidString).caf")
        file = try AVAudioFile(forWriting: url, settings: Self.format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    public func append(_ chunk: URL, for segment: UUID) throws {
        guard let file else { return }
        let samples = try ParakeetProvider.samples(of: chunk)
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let start = Double(file.length) / Self.format.sampleRate
        try file.write(from: buffer)
        placements.append(Placement(segment: segment, start: start, end: Double(file.length) / Self.format.sampleRate))
    }

    /// Finds the voices behind each Them segment; empty when no call audio was collected.
    func voiceTurns() async throws -> [UUID: [VoiceTurn]] {
        file = nil
        guard !placements.isEmpty else { return [:] }
        let audio = try ParakeetProvider.samples(of: url)
        let result = try await SpeakerDetection.abandoningOnCancel {
            try await SpeakerDetection.installedDiarizer(from: SpeakerDetection.directory).diarize(audioArray: audio, options: nil, progressCallback: nil)
        }
        try Task.checkCancellation()
        return SpeakerDetection.voiceTurns(turns: result.segments, placements: placements)
    }

    /// Writes one stretch of a segment's call audio to its own file, in seconds from the segment's start.
    func audio(of segment: UUID, from start: TimeInterval, to end: TimeInterval) throws -> URL {
        guard file == nil, let placement = placements.first(where: { $0.segment == segment }) else { throw CocoaError(.fileReadUnknown) }
        let source = try AVAudioFile(forReading: url)
        let first = AVAudioFramePosition((placement.start + start) * Self.format.sampleRate)
        let last = AVAudioFramePosition(min(placement.end, placement.start + end) * Self.format.sampleRate)
        guard last > first, let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: AVAudioFrameCount(last - first)) else {
            throw CocoaError(.fileReadUnknown)
        }
        source.framePosition = first
        try source.read(into: buffer, frameCount: AVAudioFrameCount(last - first))
        let piece = FileManager.default.temporaryDirectory.appending(path: "betterwispr-meeting-\(UUID().uuidString).caf")
        do {
            try AVAudioFile(forWriting: piece, settings: Self.format.settings, commonFormat: .pcmFormatFloat32, interleaved: false).write(from: buffer)
        } catch {
            try? FileManager.default.removeItem(at: piece)
            throw error
        }
        return piece
    }

    public nonisolated func discard() {
        try? FileManager.default.removeItem(at: url)
    }
}
