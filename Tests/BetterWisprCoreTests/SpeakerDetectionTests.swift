import FluidAudio
import Foundation
import Testing
@testable import BetterWisprCore

private func turn(_ voice: String, _ start: Float, _ end: Float) -> TimedSpeakerSegment {
    TimedSpeakerSegment(speakerId: voice, embedding: [], startTimeSeconds: start, endTimeSeconds: end, qualityScore: 1)
}

@Test func speakerDetectionGivesEachSegmentItsLongestVoiceNumberedByFirstAppearance() {
    let ids = (0..<5).map { _ in UUID() }
    let turns = [turn("S3", 0, 5), turn("S1", 5, 12), turn("S3", 12, 20), turn("S9", 40, 41), turn("S8", 41, 42)]
    let placements = [
        SpeakerRecording.Placement(segment: ids[2], start: 10, end: 20),
        SpeakerRecording.Placement(segment: ids[0], start: 0, end: 4),
        SpeakerRecording.Placement(segment: ids[4], start: 40, end: 42),
        SpeakerRecording.Placement(segment: ids[1], start: 4, end: 10),
        SpeakerRecording.Placement(segment: ids[3], start: 20, end: 25),
    ]

    let participants = SpeakerDetection.participants(turns: turns, placements: placements)

    #expect(participants[ids[0]] == 1)
    #expect(participants[ids[1]] == 2)
    #expect(participants[ids[2]] == 1)
    #expect(participants[ids[3]] == nil)
    #expect(participants[ids[4]] == 3)
    #expect(SpeakerDetection.participants(turns: [], placements: placements).isEmpty)
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

@Test func speakerDetectionReadsThePLDAParametersAndRejectsAnEmptyTensor() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "plda-parameters.json")
    func write(_ values: [Float]) throws {
        let encoded = values.withUnsafeBytes { Data($0) }.base64EncodedString()
        try Data(#"{"tensors":{"psi":{"data_base64":"\#(encoded)"}}}"#.utf8).write(to: url)
    }

    try write([1.5, -2, 0.25])
    #expect(try SpeakerDetection.pldaPsi(from: url) == [1.5, -2, 0.25])
    try write([])
    #expect(throws: SpeakerDetectionError.self) { try SpeakerDetection.pldaPsi(from: url) }
    #expect(!SpeakerDetection.isInstalled(at: directory))
}
