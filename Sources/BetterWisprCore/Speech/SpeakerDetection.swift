@preconcurrency import AVFoundation
@preconcurrency import CoreML
import FluidAudio
import Foundation

public enum SpeakerDetectionError: LocalizedError {
    case damaged

    public var errorDescription: String? {
        "The speaker detection model is damaged. Download it again in Models."
    }
}

/// Tells the voices on the other side of a call apart after a meeting, on this Mac, with FluidAudio's offline pyannote pipeline.
public enum SpeakerDetection {
    public static var directory: URL {
        OfflineDiarizerModels.defaultModelsDirectory().appending(path: Repo.diarizer.folderName)
    }

    /// Apple fixed a crash in this pipeline's Core ML path in macOS 15 (FluidAudio issue 878).
    public static var isSupported: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))
    }

    public static var isReady: Bool { isSupported && isInstalled() }

    public static func isInstalled(at directory: URL = directory) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: ".betterwispr-installed").path)
            && ModelNames.OfflineDiarizer.requiredModels.allSatisfy { FileManager.default.fileExists(atPath: directory.appending(path: $0).path) }
    }

    /// Downloads and verifies the models after an explicit installation action.
    public static func install(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let directory = directory
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await ModelHub.download(.diarizer, to: directory.deletingLastPathComponent(), variant: "offline") {
            progress?(ParakeetProvider.downloadedFraction($0))
        }
        try Task.checkCancellation()
        _ = try loadModels(from: directory)
        try Task.checkCancellation()
        try Data(directory.lastPathComponent.utf8).write(to: directory.appending(path: ".betterwispr-installed"), options: .atomic)
    }

    /// Loads only files already on disk, so a missing or damaged model fails instead of downloading again.
    static func loadModels(from directory: URL) throws -> OfflineDiarizerModels {
        let names = ModelNames.OfflineDiarizer.self
        func model(_ name: String, on units: MLComputeUnits) throws -> MLModel {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = units
            configuration.allowLowPrecisionAccumulationOnGPU = true
            return try MLModel(contentsOf: directory.appending(path: name), configuration: configuration)
        }
        return OfflineDiarizerModels(
            segmentationModel: try model(names.segmentationPath, on: .all), fbankModel: try model(names.fbankPath, on: .cpuOnly),
            embeddingModel: try model(names.embeddingPath, on: .all), pldaRhoModel: try model(names.pldaRhoPath, on: .all),
            pldaPsi: try pldaPsi(from: directory.appending(path: names.pldaParameters)), compilationDuration: 0)
    }

    private struct PLDAParameters: Decodable {
        struct Tensors: Decodable { var psi: Tensor }
        struct Tensor: Decodable { var data_base64: String }
        var tensors: Tensors
    }

    /// Adapted from FluidAudio's private `OfflineDiarizerModels.loadPLDAPsi`.
    static func pldaPsi(from url: URL) throws -> [Double] {
        let encoded = try JSONDecoder().decode(PLDAParameters.self, from: Data(contentsOf: url)).tensors.psi.data_base64
        guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters), data.count >= MemoryLayout<Float>.size else {
            throw SpeakerDetectionError.damaged
        }
        var floats = [Float](repeating: 0, count: data.count / MemoryLayout<Float>.size)
        _ = floats.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return floats.map(Double.init)
    }

    /// Gives each segment the voice heard longest within it, numbering voices 1, 2, 3 in the order they first speak.
    static func participants(turns: [TimedSpeakerSegment], placements: [SpeakerRecording.Placement]) -> [UUID: Int] {
        var numbers: [String: Int] = [:]
        var participants: [UUID: Int] = [:]
        for placement in placements.sorted(by: { $0.start < $1.start }) {
            var heard: [String: Double] = [:]
            for turn in turns {
                let overlap = min(placement.end, Double(turn.endTimeSeconds)) - max(placement.start, Double(turn.startTimeSeconds))
                if overlap > 0 { heard[turn.speakerId, default: 0] += overlap }
            }
            guard let voice = heard.sorted(by: { $0.key < $1.key }).max(by: { $0.value < $1.value })?.key else { continue }
            let number = numbers[voice] ?? numbers.count + 1
            numbers[voice] = number
            participants[placement.segment] = number
        }
        return participants
    }
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
        let samples = try AudioConverter().resampleAudioFile(chunk)
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let start = Double(file.length) / Self.format.sampleRate
        try file.write(from: buffer)
        placements.append(Placement(segment: segment, start: start, end: Double(file.length) / Self.format.sampleRate))
    }

    /// Numbers the voice behind each Them segment; empty when no call audio was collected.
    public func participants() async throws -> [UUID: Int] {
        file = nil
        guard !placements.isEmpty else { return [:] }
        let diarizer = OfflineDiarizerManager()
        diarizer.initialize(models: try SpeakerDetection.loadModels(from: SpeakerDetection.directory))
        let result = try await diarizer.process(url)
        return SpeakerDetection.participants(turns: result.segments, placements: placements)
    }

    public nonisolated func discard() {
        try? FileManager.default.removeItem(at: url)
    }
}
