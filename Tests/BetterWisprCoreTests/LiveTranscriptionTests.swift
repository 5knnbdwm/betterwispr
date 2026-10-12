import FluidAudio
import Foundation
import Testing
@testable import BetterWisprCore

private func words(_ text: String, confidence: Float = 1, from start: TimeInterval = 0) -> [TimedWord] {
    text.split(separator: " ").enumerated().map { index, word in
        TimedWord(text: String(word), startTime: start + Double(index), endTime: start + Double(index) + 1, confidence: confidence)
    }
}

private let spoken = "One two three four five six. Seven eight. Nine ten. Eleven twelve"

@Test func firstPassIsHypothesisAndThreeAgreeingPassesConfirmThroughTheThirdLastSentence() {
    var engine = WordAgreementEngine()
    #expect(engine.process(words(spoken)) == LiveTranscript(confirmed: "", hypothesis: spoken))
    #expect(engine.process(words(spoken)).confirmed == "")
    #expect(engine.process(words(spoken)).confirmed == "")
    #expect(engine.seekTime == 0)
    #expect(engine.process(words(spoken)) == LiveTranscript(confirmed: "One two three four five six.", hypothesis: "Seven eight. Nine ten. Eleven twelve"))
    #expect(engine.seekTime == 6)
    #expect(engine.process(words("Seven eight. Nine ten. Eleven twelve.", from: 6)).confirmed == "One two three four five six.")
}

@Test func lowConfidencePassShowsAsHypothesisAndRestartsTheCount() {
    var engine = WordAgreementEngine()
    _ = engine.process(words(spoken))
    _ = engine.process(words(spoken))
    #expect(engine.process(words(spoken), passConfidence: 0.1) == LiveTranscript(confirmed: "", hypothesis: spoken))
    #expect(engine.process(words(spoken)).confirmed == "")
    #expect(engine.process(words(spoken)).confirmed == "")
    #expect(engine.process(words(spoken)).confirmed == "One two three four five six.")
}

@Test func disagreeingPassRestartsTheCount() {
    var engine = WordAgreementEngine()
    _ = engine.process(words(spoken))
    _ = engine.process(words(spoken))
    _ = engine.process(words("One too three four five six. Seven eight. Nine ten. Eleven twelve"))
    #expect(engine.process(words(spoken)).confirmed == "")
    #expect(engine.process(words(spoken)).confirmed == "")
    #expect(engine.process(words(spoken)).confirmed == "")
    #expect(engine.process(words(spoken)).confirmed == "One two three four five six.")
}

@Test func punctuationNeverBreaksAgreementButAMovedSentenceEndBlocksConfirmation() {
    var engine = WordAgreementEngine()
    _ = engine.process(words(spoken))
    _ = engine.process(words("One, two three four five six. Seven eight. Nine ten. Eleven twelve"))
    _ = engine.process(words(spoken))
    let moved = "One two three four five six Seven eight. Nine ten. Eleven twelve."
    #expect(engine.process(words(moved)).confirmed == "")
    #expect(engine.process(words(moved)).confirmed == "One two three four five six Seven eight.")
}

@Test func lowConfidenceWordsAtTheBoundaryBlockConfirmation() {
    var engine = WordAgreementEngine()
    for _ in 0..<3 { _ = engine.process(words(spoken, confidence: 0.5)) }
    #expect(engine.process(words(spoken, confidence: 0.5)).confirmed == "")
    #expect(engine.process(words(spoken)).confirmed == "One two three four five six.")
}

@Test func fragmentsShorterThanFiveWordsAreNeverConfirmed() {
    var engine = WordAgreementEngine()
    for _ in 0..<5 {
        #expect(engine.process(words("One two. Three four. Five six. Seven eight.")).confirmed == "")
    }
}

@Test func tokensMergeIntoWordsWithAveragedConfidence() {
    let tokens = [
        TokenTiming(token: "▁Hel", tokenId: 1, startTime: 0, endTime: 0.1, confidence: 1),
        TokenTiming(token: "lo", tokenId: 2, startTime: 0.1, endTime: 0.2, confidence: 0.5),
        TokenTiming(token: "▁world.", tokenId: 3, startTime: 0.3, endTime: 0.5, confidence: 1),
    ]
    #expect(TimedWord.words(from: tokens) == [
        TimedWord(text: "Hello", startTime: 0, endTime: 0.2, confidence: 0.75),
        TimedWord(text: "world.", startTime: 0.3, endTime: 0.5, confidence: 1),
    ])
    #expect(TimedWord.words(from: []).isEmpty)
}

@MainActor
private final class PassLog {
    var sliceCounts: [Int] = []
    var updates: [LiveTranscript] = []
    var started = 0
    var finished = 0
}

@Test @MainActor func liveTranscriberPassesOnlyWhileRunningAndOnlyOverNewAudio() async throws {
    let transcriber = LiveTranscriber(interval: .milliseconds(20))
    let silence = [Float](repeating: 0, count: 32_000)
    transcriber.append(silence)
    #expect(transcriber.state == .idle)
    transcriber.beginBuffering()
    #expect(transcriber.state == .buffering)
    transcriber.append(silence)
    let log = PassLog()
    transcriber.onUpdate = { log.updates.append($0) }
    transcriber.start { samples in
        log.sliceCounts.append(samples.count)
        return LivePass(words: words("Hello there"), confidence: 1)
    }
    #expect(transcriber.state == .running)
    try await Task.sleep(for: .milliseconds(300))
    #expect(log.sliceCounts == [48_000])
    #expect(log.updates == [LiveTranscript(confirmed: "", hypothesis: "Hello there")])
    transcriber.append([Float](repeating: 0, count: 1_000))
    try await Task.sleep(for: .milliseconds(300))
    #expect(log.sliceCounts.count == 1)
    transcriber.append(silence)
    try await Task.sleep(for: .milliseconds(300))
    #expect(log.sliceCounts == [48_000, 81_000])
    await transcriber.stop()
    #expect(transcriber.state == .stopped)
    transcriber.append(silence)
    try await Task.sleep(for: .milliseconds(100))
    #expect(log.sliceCounts.count == 2)
}

@Test @MainActor func stopWaitsForTheInFlightPassAndDropsItsResult() async throws {
    let transcriber = LiveTranscriber(interval: .milliseconds(20))
    transcriber.beginBuffering()
    transcriber.append([Float](repeating: 0, count: 32_000))
    let log = PassLog()
    transcriber.onUpdate = { log.updates.append($0) }
    transcriber.start { _ in
        log.started += 1
        await Task { try? await Task.sleep(for: .milliseconds(200)) }.value
        log.finished += 1
        return LivePass(words: words("Hello there"), confidence: 1)
    }
    let deadline = ContinuousClock.now + .seconds(2)
    while log.started == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(log.started == 1 && log.finished == 0)
    await transcriber.stop()
    #expect(transcriber.state == .stopped)
    #expect(log.finished == 1)
    #expect(log.updates.isEmpty && transcriber.transcript.isEmpty)
}

@Test @MainActor func cancelEndsTheSessionFromAnyStateAndStartIsThenIgnored() async throws {
    let transcriber = LiveTranscriber(interval: .milliseconds(20))
    transcriber.beginBuffering()
    transcriber.append([Float](repeating: 0, count: 32_000))
    transcriber.cancel()
    #expect(transcriber.state == .stopped)
    let log = PassLog()
    transcriber.start { samples in
        log.sliceCounts.append(samples.count)
        return LivePass(words: [], confidence: 1)
    }
    #expect(transcriber.state == .stopped)
    try await Task.sleep(for: .milliseconds(100))
    #expect(log.sliceCounts.isEmpty)
    transcriber.beginBuffering()
    #expect(transcriber.state == .stopped)
}
