import Foundation
import Testing
@testable import BetterWisprCore
@testable import BetterWispr

private func exchange(citing meetingID: UUID, question: String = "When does the deck arrive?") -> AskExchange {
    let line = MeetingLine(meetingID: meetingID, segmentID: UUID(), label: "00:12 Debra", text: "I'll send it Friday.")
    return AskExchange(question: question, answer: MeetingAnswer(text: "Friday [2].", citations: [.init(number: 2, line: line)], modelName: "Fake model"))
}

private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

@Test func meetingAskThreadRoundTripsWithItsCitations() throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = MeetingStore(directory: folder)
    var meeting = Meeting(title: "Deck review", modelName: "Parakeet", language: "en")
    meeting.askThread = [exchange(citing: meeting.id), exchange(citing: meeting.id, question: "Who sends it?")]

    try store.save(meeting)

    let loaded = store.load()
    #expect(loaded.unreadable.isEmpty)
    #expect(loaded.meetings == [meeting])
    #expect(loaded.meetings.first?.askThread?.first?.answer.citations.first?.line.text == "I'll send it Friday.")
}

@Test func meetingFileSavedBeforeAskThreadsStillLoads() throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let id = UUID()
    try Data("""
        {"version": 1, "meeting": {"id": "\(id.uuidString)", "title": "Old", "createdAt": 700000000, "duration": 60, "notes": "A thought",
        "segments": [], "modelName": "Parakeet", "language": "en"}}
        """.utf8).write(to: folder.appendingPathComponent("\(id.uuidString).json"))

    let loaded = MeetingStore(directory: folder).load()

    #expect(loaded.unreadable.isEmpty)
    #expect(loaded.meetings.map(\.id) == [id])
    #expect(loaded.meetings.first?.askThread == nil)
}

@Test func askThreadStoreRoundTripsAndStartsEmpty() throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = AskThreadStore(url: folder.appendingPathComponent("ask.json"))
    #expect(try store.load().isEmpty)
    let saved = [exchange(citing: UUID()), exchange(citing: UUID(), question: "Who sends it?")]

    try store.save(saved)

    #expect(try store.load() == saved)
    let permissions = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
}

@Test func askThreadStoreRefusesCorruptAndNewerFiles() throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let corrupt = AskThreadStore(url: folder.appendingPathComponent("corrupt.json"))
    let newer = AskThreadStore(url: folder.appendingPathComponent("newer.json"))
    try Data("{not json".utf8).write(to: corrupt.url)
    try Data(#"{"version": 2, "exchanges": []}"#.utf8).write(to: newer.url)

    #expect(throws: (any Error).self) { try corrupt.load() }
    #expect(throws: (any Error).self) { try newer.load() }
}

@MainActor
@Test func allMeetingsThreadIsSavedNextToMeetingsAndPrunedWhenACitedMeetingIsDeleted() throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = MeetingStore(directory: folder.appendingPathComponent("Meetings"))
    let cited = Meeting(title: "Cited", notes: "A thought", modelName: "Parakeet", language: "en")
    let other = Meeting(title: "Other", notes: "Another thought", modelName: "Parakeet", language: "en")
    try store.save(cited)
    try store.save(other)
    let model = MeetingModel(store: store)

    model.append(exchange(citing: cited.id), to: .allMeetings)
    model.append(exchange(citing: other.id, question: "Who sends it?"), to: .allMeetings)
    model.delete(cited.id)

    let reloaded = MeetingModel(store: store)
    #expect(reloaded.message == nil)
    #expect(reloaded.thread(.allMeetings).map(\.question) == ["Who sends it?"])
    #expect(store.load().unreadable.isEmpty)

    reloaded.clear(.allMeetings)
    #expect(MeetingModel(store: store).thread(.allMeetings).isEmpty)
}

@MainActor
@Test func unreadableAllMeetingsThreadIsReportedAndNeverOverwritten() throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = MeetingStore(directory: folder.appendingPathComponent("Meetings"))
    let meeting = Meeting(title: "Kept", notes: "A thought", modelName: "Parakeet", language: "en")
    try store.save(meeting)
    let askFile = folder.appendingPathComponent("ask.json")
    let corrupt = Data("{not json".utf8)
    try corrupt.write(to: askFile)

    let model = MeetingModel(store: store)
    model.append(exchange(citing: meeting.id), to: .allMeetings)
    model.clear(.allMeetings)

    #expect(model.message?.contains("ask.json couldn’t be read and was left untouched") == true)
    #expect(try Data(contentsOf: askFile) == corrupt)
    #expect(model.meetings == [meeting])
}

@MainActor
@Test func meetingAskThreadIsSavedWithTheMeetingAndCleared() async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = MeetingStore(directory: folder.appendingPathComponent("Meetings"))
    let meeting = Meeting(title: "Deck review", notes: "A thought", modelName: "Parakeet", language: "en")
    try store.save(meeting)
    let model = MeetingModel(store: store)
    let asked = exchange(citing: meeting.id)

    model.append(asked, to: .meeting(meeting.id))
    #expect(model.thread(.meeting(meeting.id)) == [asked])
    #expect(model.thread(.allMeetings).isEmpty)
    #expect(try await saved([asked], for: meeting.id, in: store))

    model.clear(.meeting(meeting.id))
    #expect(try await saved(nil, for: meeting.id, in: store))
}

private func saved(_ thread: [AskExchange]?, for id: UUID, in store: MeetingStore) async throws -> Bool {
    for _ in 0..<40 {
        if store.load().meetings.first(where: { $0.id == id })?.askThread == thread { return true }
        try await Task.sleep(for: .milliseconds(50))
    }
    return false
}
