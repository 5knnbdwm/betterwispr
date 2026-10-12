import AVFoundation
import Foundation

/// One second of quiet 16 kHz noise for throwaway transcriptions. Never zeros, because Whisper skips digital silence.
public enum WarmUpClip {
    public static func url() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "betterwispr-warm-up.caf")
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][index] = .random(in: -0.001...0.001) }
        let partial = FileManager.default.temporaryDirectory.appending(path: "betterwispr-warm-up-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: partial) }
        try AVAudioFile(forWriting: partial, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            .write(from: buffer)
        if !FileManager.default.fileExists(atPath: url.path) { try FileManager.default.moveItem(at: partial, to: url) }
        return url
    }
}
