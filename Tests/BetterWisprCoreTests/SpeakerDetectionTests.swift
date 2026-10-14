import Foundation
import Testing
@testable import BetterWisprCore

private func turn(_ voice: String, _ start: TimeInterval, _ end: TimeInterval) -> VoiceTurn {
    VoiceTurn(voice: voice, start: start, end: end)
}

@Test func speakerDetectionSplitsSegmentsAtVoiceChangesAndFoldsShortInterjections() {
    let ids = (0..<8).map { _ in UUID() }
    let turns = [
        turn("S1", 50, 53), turn("S2", 55, 60), turn("S3", 0, 5), turn("S1", 5, 12), turn("S3", 12, 20), turn("S9", 40, 40.5), turn("S8", 40.5, 42),
        turn("S1", 70, 75), turn("S2", 75, 75.4), turn("S1", 75.4, 80), turn("S1", 90, 96), turn("S2", 95, 100),
    ]
    let placements = [
        SpeakerRecording.Placement(segment: ids[0], start: 0, end: 4),
        SpeakerRecording.Placement(segment: ids[1], start: 4.5, end: 10),
        SpeakerRecording.Placement(segment: ids[2], start: 10, end: 20),
        SpeakerRecording.Placement(segment: ids[3], start: 20, end: 25),
        SpeakerRecording.Placement(segment: ids[4], start: 40, end: 42),
        SpeakerRecording.Placement(segment: ids[5], start: 50, end: 60),
        SpeakerRecording.Placement(segment: ids[6], start: 70, end: 80),
        SpeakerRecording.Placement(segment: ids[7], start: 90, end: 100),
    ]

    let voices = SpeakerDetection.voiceTurns(turns: turns, placements: placements, shortest: 1)

    #expect(voices[ids[0]] == [VoiceTurn(voice: "S3", start: 0, end: 4)])
    #expect(voices[ids[1]] == [VoiceTurn(voice: "S1", start: 0, end: 5.5)])
    #expect(voices[ids[2]] == [VoiceTurn(voice: "S1", start: 0, end: 2), VoiceTurn(voice: "S3", start: 2, end: 10)])
    #expect(voices[ids[3]] == nil)
    #expect(voices[ids[4]] == [VoiceTurn(voice: "S8", start: 0, end: 2)])
    #expect(voices[ids[5]] == [VoiceTurn(voice: "S1", start: 0, end: 4), VoiceTurn(voice: "S2", start: 4, end: 10)])
    #expect(voices[ids[6]] == [VoiceTurn(voice: "S1", start: 0, end: 10)])
    #expect(voices[ids[7]] == [VoiceTurn(voice: "S1", start: 0, end: 6), VoiceTurn(voice: "S2", start: 6, end: 10)])
    #expect(SpeakerDetection.voiceTurns(turns: [], placements: placements).isEmpty)
}

@MainActor
@Test func speakerLabelsTranscribeMixedSegmentsAgainInPiecesAndKeepTextWhenAPieceFails() async throws {
    let me = MeetingSegment(speaker: .me, start: 0, duration: 3, text: "Shall we start?", rawText: "shall we start")
    let solo = MeetingSegment(speaker: .them, start: 3, duration: 4, text: "Sure.", rawText: "sure")
    let mixed = MeetingSegment(speaker: .them, start: 7, duration: 10, text: "I can take it. No, let me.", rawText: "i can take it no let me")
    let failing = MeetingSegment(speaker: .them, start: 17, duration: 6, text: "Fine by me, thanks.", rawText: "fine by me thanks")
    let unheard = MeetingSegment(speaker: .them, start: 23, duration: 2, text: "Hmm.", rawText: "hmm")
    let turns = [
        solo.id: [VoiceTurn(voice: "B", start: 0, end: 4)],
        mixed.id: [VoiceTurn(voice: "A", start: 0, end: 6), VoiceTurn(voice: "B", start: 6, end: 10)],
        failing.id: [VoiceTurn(voice: "C", start: 0, end: 2), VoiceTurn(voice: "A", start: 2, end: 6)],
    ]
    var written: [URL] = []

    let labelled = try await SpeakerDetection.label([me, solo, mixed, failing, unheard], turns: turns, audio: { _, _ in
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data().write(to: url)
        written.append(url)
        return url
    }) { _, start, duration in
        if start >= 17 { throw CocoaError(.fileReadCorruptFile) }
        return MeetingSegment(speaker: .them, start: start, duration: duration, text: start == 7 ? "I can take it." : "No, let me.", rawText: "")
    }

    #expect(labelled.map(\.text) == ["Shall we start?", "Sure.", "I can take it.", "No, let me.", "Fine by me, thanks.", "Hmm."])
    #expect(labelled.map(\.start) == [0, 3, 7, 13, 17, 23])
    #expect(labelled.map(\.participant) == [nil, 1, 2, 1, 2, nil])
    #expect(written.count == 3)
    #expect(written.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
}

@Test func speakerLabelsUseGivenNamesAndFallBackToNumbers() {
    let me = MeetingSegment(speaker: .me, start: 0, duration: 2, text: "Can we ship Friday?", rawText: "", participant: 1)
    let them = MeetingSegment(speaker: .them, start: 2, duration: 2, text: "Probably.", rawText: "")
    let ana = MeetingSegment(speaker: .them, start: 4, duration: 2, text: "Only if QA signs off.", rawText: "", participant: 2)
    let bo = MeetingSegment(speaker: .them, start: 6, duration: 2, text: "Agreed.", rawText: "", participant: 1)

    #expect(me.label(names: [1: "Ana"]) == "Me")
    #expect(them.label(names: [1: "Ana"]) == "Them")
    #expect(ana.label() == "Speaker 2")
    #expect(ana.label(names: [2: "  Ana "]) == "Ana")
    #expect(ana.label(names: [2: " "]) == "Speaker 2")

    var meeting = Meeting(modelName: "Parakeet", language: "en")
    for segment in [bo, ana, them, me] { meeting.insert(segment) }
    meeting.participantNames = [2: "Ana"]
    #expect(meeting.participants == [1, 2])
    #expect(meeting.transcript.components(separatedBy: "\n").map { $0.components(separatedBy: "] ").last ?? "" } == [
        "Me: Can we ship Friday?", "Them: Probably.", "Ana: Only if QA signs off.", "Speaker 1: Agreed.",
    ])
    #expect(TranscriptChunker.chunks(meeting.segments, names: meeting.participantNames, budget: 500) == [
        "Me: Can we ship Friday?\nThem: Probably.\nAna: Only if QA signs off.\nSpeaker 1: Agreed.",
    ])
}

@Test func meetingsKeepSpeakerNamesAndLoadFilesSavedBeforeSpeakers() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = MeetingStore(directory: directory)
    var meeting = Meeting(modelName: "Parakeet", language: "en")
    meeting.insert(MeetingSegment(speaker: .them, start: 0, duration: 2, text: "Hello", rawText: "hello", participant: 2))
    meeting.participantNames = [2: "Ana"]
    try store.save(meeting)
    #expect(store.load().meetings == [meeting])

    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(meeting)) as? [String: Any])
    json["participantNames"] = nil
    json["segments"] = (json["segments"] as? [[String: Any]])?.map { $0.filter { $0.key != "participant" } }
    let legacy = try JSONDecoder().decode(Meeting.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(legacy.participantNames == nil)
    #expect(legacy.segments.map(\.participant) == [nil])
    #expect(legacy.segments.map(\.text) == ["Hello"])
}

@Test func speakerDetectionIsInstalledOnlyWithTheMarkerAndEveryPinnedModel() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func add(_ model: String) throws {
        try FileManager.default.createDirectory(at: directory.appending(path: model), withIntermediateDirectories: true)
    }
    let marker = directory.appending(path: ".betterwispr-installed")

    try Data().write(to: marker)
    #expect(!SpeakerDetection.isInstalled(at: directory))
    try add("speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc")
    try add("speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc")
    try add("speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc")
    try add("speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc")
    #expect(!SpeakerDetection.isInstalled(at: directory))
    try add("speaker_segmenter/pyannote-v3/W32A32/SpeakerSegmenter.mlmodelc")
    #expect(SpeakerDetection.isInstalled(at: directory))
    try FileManager.default.removeItem(at: marker)
    #expect(!SpeakerDetection.isInstalled(at: directory))
}

@Test func speakerDetectionStopsWaitingForWorkThatIgnoresCancellation() async throws {
    #expect(try await SpeakerDetection.abandoningOnCancel { 42 } == 42)
    await #expect(throws: CocoaError.self) {
        try await SpeakerDetection.abandoningOnCancel { () async throws -> Int in throw CocoaError(.fileReadCorruptFile) }
    }

    let clock = ContinuousClock()
    let started = clock.now
    let waiting = Task {
        try await SpeakerDetection.abandoningOnCancel {
            await Task.detached { try? await Task.sleep(for: .seconds(30)) }.value
            return 1
        }
    }
    try await Task.sleep(for: .milliseconds(100))
    waiting.cancel()
    await #expect(throws: CancellationError.self) { try await waiting.value }
    #expect(clock.now - started < .seconds(5))
}
