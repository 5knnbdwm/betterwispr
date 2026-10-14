@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import BetterWisprCore

private func mediaFile(seconds: Double, silent: [Range<Double>], tone: Bool = true) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "betterwispr-test-\(UUID().uuidString).wav")
    let rate = 44_100.0
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
    let file = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
    ])
    let frames = Int(rate)
    for second in 0..<Int(seconds) {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames {
            let time = Double(second) + Double(frame) / rate
            let value: Float = tone && !silent.contains { $0.contains(time) } ? 0.2 * sin(Float(time) * 2 * .pi * 300) : 0
            buffer.floatChannelData![0][frame] = value
            buffer.floatChannelData![1][frame] = value
        }
        try file.write(from: buffer)
    }
    return url
}

private func chunks(of url: URL) async throws -> (audio: MediaAudio, chunks: [MediaChunk]) {
    let audio = try await MediaAudio(url: url)
    var chunks: [MediaChunk] = []
    while let chunk = try await audio.next() { chunks.append(chunk) }
    return (audio, chunks)
}

@Test func mediaCutsAtTheFirstQuietestSmoothedFrameInTheWindow() {
    var gap = [Float](repeating: 1, count: 6_000)
    gap[3_200] = 0
    for frame in 5_000..<5_100 { gap[frame] = 0 }
    #expect(MediaAudio.cut(levels: gap, minimum: 3_000, maximum: 5_950) == 5_015)
    #expect(MediaAudio.cut(levels: [Float](repeating: 1, count: 6_000), minimum: 3_000, maximum: 5_950) == 3_000)
    var outside = [Float](repeating: 1, count: 6_200)
    for frame in Array(1_000..<1_100) + Array(6_000..<6_100) { outside[frame] = 0 }
    #expect(MediaAudio.cut(levels: outside, minimum: 3_000, maximum: 5_950) == 3_000)
    #expect(MediaAudio.cut(levels: [Float](repeating: 1, count: 5_960), minimum: 3_000, maximum: 5_950) == 5_949)
}

@Test func mediaAudioCutsInSilentGapsIntoContiguousChunksThatCoverTheFile() async throws {
    let url = try mediaFile(seconds: 130, silent: [40..<41, 85..<86])
    defer { try? FileManager.default.removeItem(at: url) }
    let (audio, chunks) = try await chunks(of: url)
    defer { for chunk in chunks { try? FileManager.default.removeItem(at: chunk.url) } }

    #expect(abs(audio.duration - 130) < 0.01)
    #expect(chunks.count == 3)
    #expect((40.0...41).contains(chunks[0].start + chunks[0].duration))
    #expect((85.0...86).contains(chunks[1].start + chunks[1].duration))
    #expect(chunks.allSatisfy { $0.duration <= 59.5 })
    #expect(chunks.first?.start == 0)
    #expect(zip(chunks, chunks.dropFirst()).allSatisfy { $0.start + $0.duration == $1.start })
    #expect(abs(chunks.last.map { $0.start + $0.duration - 130 } ?? 130) < 0.01)
    for chunk in chunks {
        let file = try AVAudioFile(forReading: chunk.url)
        #expect(file.fileFormat.sampleRate == 16_000 && file.fileFormat.channelCount == 1)
        #expect(Double(file.length) == chunk.duration * 16_000)
    }
    #expect(try await audio.next() == nil)
}

@Test func silentMediaStillYieldsChunksAtTheShortestLength() async throws {
    let url = try mediaFile(seconds: 70, silent: [], tone: false)
    defer { try? FileManager.default.removeItem(at: url) }
    let (_, chunks) = try await chunks(of: url)
    defer { for chunk in chunks { try? FileManager.default.removeItem(at: chunk.url) } }

    #expect(chunks.count == 2)
    #expect(chunks.first?.duration == 30)
    #expect(abs((chunks.last?.duration ?? 0) - 40) < 0.01)
}

@Test func mediaAudioRejectsAFileItCannotReadWithTheSupportedFormats() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "betterwispr-test-\(UUID().uuidString).mp3")
    try Data("not audio".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    await #expect(throws: MediaAudioError.unreadable(url.lastPathComponent)) { try await MediaAudio(url: url) }
    #expect(MediaAudioError.unreadable("talk.mkv").localizedDescription.contains("MP3, M4A, AAC, WAV, AIFF, CAF, FLAC, MP4, MOV or M4V"))
}
