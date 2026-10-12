@preconcurrency import AVFoundation
import Foundation

/// Converts capture buffers into one format as the microphone changes format; unchecked because `convert` runs its input block synchronously and each owner calls it under its own lock.
final class FormatConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private var pending: AVAudioPCMBuffer?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard buffer.format != format else {
            converter = nil
            return buffer
        }
        if converter?.inputFormat != buffer.format || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate).rounded(.up))
        guard let converter, let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AudioRecordingError.unavailable
        }
        pending = buffer
        defer { pending = nil }
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in
            guard let input = self.pending else {
                status.pointee = .noDataNow
                return nil
            }
            self.pending = nil
            status.pointee = .haveData
            return input
        }
        if status == .error { throw error ?? AudioRecordingError.unavailable }
        return output
    }
}

/// Unchecked because a lock serializes the converter with capture-worker callbacks, and only copied sample arrays leave it.
final class LiveSampleTap: @unchecked Sendable {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let lock = NSLock()
    private let formatter = FormatConverter()
    private let deliver: @Sendable ([Float]) -> Void

    init(deliver: @escaping @Sendable ([Float]) -> Void) {
        self.deliver = deliver
    }

    func receive(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let converted = try? formatter.convert(buffer, to: Self.format), converted.frameLength > 0,
              let channel = converted.floatChannelData?[0] else { return }
        deliver(Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))))
    }
}
