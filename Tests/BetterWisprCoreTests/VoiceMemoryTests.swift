import Foundation
import Testing
@testable import BetterWisprCore

private func voice(at angle: Double, length: Float = 1) -> [Float] {
    [Float(cos(angle)) * length, Float(sin(angle)) * length]
}

private func known(_ name: String, _ embedding: [Float], meeting: UUID = UUID(), participant: Int = 1) -> KnownVoice {
    KnownVoice(name: name, meetingID: meeting, participant: participant, embedding: embedding)
}

@Test func rememberedVoicesNameOnlyVoicesWithinSpeakerKitsClusteringDistance() {
    let remembered = [known("Ana", voice(at: 0)), known("Bo", voice(at: .pi / 2))]

    let names = SpeakerDetection.recognise([
        1: voice(at: .pi / 2 - 0.1, length: 0.2),
        2: voice(at: .pi),
        3: [1, 0, 0],
        4: [0, 0],
    ], among: remembered)

    #expect(names == [1: "Bo"])
    #expect(SpeakerDetection.recognise([1: voice(at: 0.60, length: 7)], among: remembered) == [1: "Ana"])
    #expect(SpeakerDetection.recognise([1: voice(at: 0.62)], among: remembered).isEmpty)
    #expect(SpeakerDetection.recognise([1: voice(at: 0)], among: []).isEmpty)
}

@Test func eachRememberedNameGoesToTheNearestVoiceOnly() {
    let remembered = [known("Ana", voice(at: 0)), known(" ana", voice(at: 0.4)), known("Bo", voice(at: 0.55))]

    let names = SpeakerDetection.recognise([1: voice(at: 0.43), 2: voice(at: 0.01), 3: voice(at: 0.2)], among: remembered)

    #expect(names == [2: "Ana", 1: "Bo"])
}

@Test func namingAVoiceRemembersItUnlessItKeepsTheRecognisedName() {
    let meeting = UUID()
    let voices: [Int: [Float]] = [1: [1, 0], 2: [0, 1], 3: [1, 1]]

    let named = SpeakerDetection.namedVoices(voices, names: [1: " Ana ", 2: "BO", 3: "  ", 4: "Cy"], recognised: [2: "Bo"], in: meeting)
    #expect(named == [known("Ana", [1, 0], meeting: meeting, participant: 1)])

    let renamed = SpeakerDetection.namedVoices(voices, names: [1: "Ana", 2: "Di"], recognised: [2: "Bo"], in: meeting)
    #expect(renamed == [known("Ana", [1, 0], meeting: meeting, participant: 1), known("Di", [0, 1], meeting: meeting, participant: 2)])

    #expect(SpeakerDetection.namedVoices(voices, names: nil, recognised: [:], in: meeting).isEmpty)
}

@Test func voiceStoreReplacesOneMeetingsVoicesAndNeverWritesOverAnUnreadableFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = VoiceStore(url: directory.appendingPathComponent("Voices.json"))
    let first = UUID()
    let second = UUID()
    #expect(try store.load().isEmpty)

    try store.replaceVoices(from: first, with: [known("Ana", [1, 0], meeting: first)])
    try store.replaceVoices(from: second, with: [known("Bo", [0, 1], meeting: second)])
    try store.replaceVoices(from: first, with: [known("Cy", [1, 1], meeting: first, participant: 2)])
    #expect(try store.load() == [known("Bo", [0, 1], meeting: second), known("Cy", [1, 1], meeting: first, participant: 2)])
    let permissions = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)

    let unreadable = Data("not voices".utf8)
    try unreadable.write(to: store.url)
    #expect(throws: (any Error).self) { try store.replaceVoices(from: first, with: []) }
    #expect(try Data(contentsOf: store.url) == unreadable)

    try Data(#"{"version":2,"voices":[]}"#.utf8).write(to: store.url)
    #expect(throws: StoreError.self) { try store.load() }

    try store.forget()
    #expect(!FileManager.default.fileExists(atPath: store.url.path))
    try store.forget()
    #expect(try store.load().isEmpty)
}
