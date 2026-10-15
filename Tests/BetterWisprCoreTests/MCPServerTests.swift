import Foundation
import Testing
@testable import BetterWisprCore

private struct Workspace {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var meetings: MeetingStore { MeetingStore(directory: root.appendingPathComponent("Meetings")) }
    var settings: LocalStore { LocalStore(directory: root) }
    var server: MCPServer { MCPServer(meetings: meetings, settings: settings) }

    func connectedApps(_ isOn: Bool) throws {
        var state = SavedState()
        state.settings.mcpServer = isOn
        try settings.save(state)
    }

    func send(_ line: String) throws -> [String: Any] {
        let reply = try #require(server.reply(to: line))
        #expect(!reply.contains("\n"))
        return try #require(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
    }

    func call(_ tool: String, _ arguments: [String: Any] = [:]) throws -> (text: String, isError: Bool) {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": ["name": tool, "arguments": arguments]]
        let result = try #require(send(String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self))["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        return (try #require(content.first?["text"] as? String), try #require(result["isError"] as? Bool))
    }
}

private func meeting(_ title: String, at date: String, duration: TimeInterval = 60, notes: String = "", segments: [MeetingSegment] = []) throws -> Meeting {
    Meeting(title: title, createdAt: try #require(ISO8601DateFormatter().date(from: date)), duration: duration, notes: notes,
            segments: segments, modelName: "test", language: "en")
}

private func line(_ text: String, at start: TimeInterval, _ speaker: Speaker = .them, participant: Int? = nil) -> MeetingSegment {
    MeetingSegment(speaker: speaker, start: start, duration: 2, text: text, rawText: text, participant: participant)
}

private func continuation(in text: String) -> Int? {
    text.firstMatch(of: /offset (\d+)/).flatMap { Int($0.1) }
}

@Test func initializeNegotiatesTheVersionEchoesTheIDAndOffersOnlyTools() throws {
    let workspace = Workspace()
    let reply = try workspace.send(#"{"jsonrpc":"2.0","id":"a1","method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#)
    #expect(reply["id"] as? String == "a1")
    let result = try #require(reply["result"] as? [String: Any])
    #expect(result["protocolVersion"] as? String == "2025-06-18")
    #expect((result["capabilities"] as? [String: Any])?.keys.sorted() == ["tools"])
    #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "betterwispr")

    let future = try #require(workspace.send(#"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#)["result"] as? [String: Any])
    #expect(future["protocolVersion"] as? String == "2025-11-25")
}

@Test func notificationsGetNoReplyAndPingAnswersEmpty() throws {
    let workspace = Workspace()
    #expect(workspace.server.reply(to: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    #expect(workspace.server.reply(to: "   ") == nil)
    let ping = try workspace.send(#"{"jsonrpc":"2.0","id":5,"method":"ping"}"#)
    #expect(ping["id"] as? Int == 5)
    #expect((ping["result"] as? [String: Any])?.isEmpty == true)
}

@Test func toolsListOffersThreeReadOnlyMeetingTools() throws {
    let result = try #require(Workspace().send(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)["result"] as? [String: Any])
    let tools = try #require(result["tools"] as? [[String: Any]])
    let byName = Dictionary(uniqueKeysWithValues: tools.map { ($0["name"] as? String ?? "", $0) })
    #expect(byName.keys.sorted() == ["get_meeting", "list_meetings", "search_meetings"])
    for tool in tools {
        #expect((tool["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool == true)
        #expect((tool["inputSchema"] as? [String: Any])?["type"] as? String == "object")
    }
    #expect((byName["get_meeting"]?["inputSchema"] as? [String: Any])?["required"] as? [String] == ["id"])
    #expect((byName["search_meetings"]?["inputSchema"] as? [String: Any])?["required"] as? [String] == ["query"])
}

@Test func everyToolRefusesMeetingDataUntilConnectedAppsIsOn() throws {
    let workspace = Workspace()
    defer { try? FileManager.default.removeItem(at: workspace.root) }
    let secret = try meeting("Acquisition talks", at: "2026-10-14T09:00:00Z", notes: "Offer is 40 million")
    try workspace.meetings.save(secret)
    let calls: [(String, [String: Any])] = [("list_meetings", [:]), ("get_meeting", ["id": secret.id.uuidString]), ("search_meetings", ["query": "offer"])]

    func expectRefused() throws {
        for (tool, arguments) in calls {
            let reply = try workspace.call(tool, arguments)
            #expect(reply.isError)
            #expect(reply.text == MCPServer.offMessage)
        }
    }

    try expectRefused()
    try workspace.connectedApps(false)
    try expectRefused()
    try Data("{".utf8).write(to: workspace.settings.stateURL)
    try expectRefused()

    try workspace.connectedApps(true)
    for (tool, arguments) in calls {
        let reply = try workspace.call(tool, arguments)
        #expect(!reply.isError)
        #expect(reply.text.contains("Acquisition talks"))
    }
}

@Test func settingsSavedBeforeConnectedAppsKeepTheServerOff() throws {
    let legacy = #"{"autoPaste":true,"language":"auto","launchAtLogin":false,"saveHistory":true,"selectedModelID":"apple","showCapsule":true,"silenceThreshold":0.002}"#
    #expect(try !JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8)).mcpServer)
}

@Test func listMeetingsShowsNewestFirstWithAttendeesSpeakersAndDuration() throws {
    let workspace = Workspace()
    defer { try? FileManager.default.removeItem(at: workspace.root) }
    try workspace.connectedApps(true)
    var standup = try meeting("Standup", at: "2026-10-14T09:00:00Z", duration: 1930, segments: [line("Shipped it", at: 4, participant: 1), line("Same", at: 9, participant: 2)])
    standup.attendees = ["Debra Lee", "sam@example.com"]
    standup.participantNames = [1: "Debra"]
    try workspace.meetings.save(standup)
    try workspace.meetings.save(try meeting("Kickoff", at: "2026-10-01T09:00:00Z"))

    let text = try workspace.call("list_meetings").text
    #expect(text.hasPrefix("Meetings 1-2 of 2, newest first."))
    #expect(try #require(text.range(of: "Standup")).lowerBound < #require(text.range(of: "Kickoff")).lowerBound)
    #expect(text.contains("id: \(standup.id.uuidString)"))
    #expect(text.contains("duration: 0:32:10"))
    #expect(text.contains("attendees: Debra Lee, sam@example.com"))
    #expect(text.contains("speakers: Debra, Speaker 2"))
    #expect(!text.contains("More meetings remain"))
}

@Test func dateFiltersTakeDateTimesOrWholeLocalDays() throws {
    let workspace = Workspace()
    defer { try? FileManager.default.removeItem(at: workspace.root) }
    try workspace.connectedApps(true)
    let lateNight = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 23, minute: 30)))
    try workspace.meetings.save(Meeting(title: "Late call", createdAt: lateNight, modelName: "test", language: "en"))
    try workspace.meetings.save(try meeting("Kickoff", at: "2026-10-01T09:00:00Z"))

    let throughDay = try workspace.call("list_meetings", ["from": "2026-10-10", "to": "2026-10-14"]).text
    #expect(throughDay.contains("Late call") && !throughDay.contains("Kickoff"))
    #expect(try !workspace.call("list_meetings", ["to": "2026-10-13"]).text.contains("Late call"))
    #expect(try workspace.call("list_meetings", ["to": "2026-10-01T09:00:00Z"]).text.contains("Kickoff"))
    let invalid = try workspace.call("list_meetings", ["from": "last week"])
    #expect(invalid.isError && invalid.text.hasPrefix("from must be a date"))
}

@Test func listMeetingsPagesFiftyAtATimeAndSaysHowToContinue() throws {
    let workspace = Workspace()
    defer { try? FileManager.default.removeItem(at: workspace.root) }
    try workspace.connectedApps(true)
    for day in 0..<51 {
        try workspace.meetings.save(Meeting(title: "Sync \(day)", createdAt: Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400), modelName: "test", language: "en"))
    }

    let first = try workspace.call("list_meetings").text
    #expect(first.hasPrefix("Meetings 1-50 of 51"))
    #expect(continuation(in: first) == 50)
    #expect(!first.contains("title: Sync 0\n"))
    let last = try workspace.call("list_meetings", ["offset": 50]).text
    #expect(last.hasPrefix("Meetings 51-51 of 51"))
    #expect(last.contains("title: Sync 0\n"))
    #expect(continuation(in: last) == nil)
    #expect(try workspace.call("list_meetings", ["offset": -1]).isError)
}

@Test func getMeetingReturnsSummaryNotesAndTranscriptWithSpeakersAndTimestamps() throws {
    let workspace = Workspace()
    defer { try? FileManager.default.removeItem(at: workspace.root) }
    try workspace.connectedApps(true)
    var review = try meeting("Budget review", at: "2026-10-14T09:00:00Z", notes: "Bring the deck",
                             segments: [line("Hello there", at: 12, .me), line("The budget is final", at: 75, participant: 1)])
    review.participantNames = [1: "Debra"]
    review.summary = MeetingSummary(overview: "Budget approved.", keyPoints: ["Costs fell"], decisions: ["Ship in May"],
                                    actionItems: [ActionItem(text: "Send recap", isDone: true), ActionItem(text: "Book room")])
    try workspace.meetings.save(review)

    let reply = try workspace.call("get_meeting", ["id": review.id.uuidString.lowercased()])
    #expect(!reply.isError)
    for expected in ["title: Budget review", "Budget approved.", "- Costs fell", "- Ship in May", "- [x] Send recap", "- [ ] Book room",
                     "Bring the deck", "[00:12] Me: Hello there", "[01:15] Debra: The budget is final"] {
        #expect(reply.text.contains(expected), "missing \(expected)")
    }
    #expect(continuation(in: reply.text) == nil)

    let missing = try workspace.call("get_meeting", ["id": UUID().uuidString])
    #expect(missing.isError && missing.text.hasPrefix("No saved meeting has id"))
    #expect(try workspace.call("get_meeting", ["id": "standup"]).isError)
    #expect(try workspace.call("get_meeting").isError)
}

@Test func getMeetingSplitsALongTranscriptIntoBoundedPartsThatResumeWhereTheLastStopped() throws {
    let workspace = Workspace()
    defer { try? FileManager.default.removeItem(at: workspace.root) }
    try workspace.connectedApps(true)
    let spoken = (0..<2000).map { "Point \($0) of the long quarterly planning discussion." }
    let long = try meeting("Offsite", at: "2026-10-14T09:00:00Z", segments: spoken.enumerated().map { line($1, at: Double($0) * 3) })
    try workspace.meetings.save(long)

    var received: [String] = []
    var offset = 0
    var parts = 0
    repeat {
        let text = try workspace.call("get_meeting", ["id": long.id.uuidString, "offset": offset]).text
        #expect(text.count < 31_000)
        received += text.components(separatedBy: "\n").filter { $0.hasPrefix("[") }.compactMap { $0.components(separatedBy: "] Them: ").last }
        parts += 1
        guard let next = continuation(in: text) else { break }
        #expect(next > offset)
        offset = next
    } while parts < 20
    #expect(parts > 1 && parts < 20)
    #expect(received == spoken)
    #expect(try workspace.call("get_meeting", ["id": long.id.uuidString, "offset": 1_000_000]).isError)
}

@Test func searchFindsAPhraseIgnoringCaseAndAccentsWithinDatesAndPointsIntoTheMeeting() throws {
    let workspace = Workspace()
    defer { try? FileManager.default.removeItem(at: workspace.root) }
    try workspace.connectedApps(true)
    let planning = try meeting("Planning", at: "2026-10-14T09:00:00Z", segments: [line("We approved the café budget", at: 30, participant: 1)])
    let review = try meeting("Review", at: "2026-10-01T09:00:00Z", notes: "Cafe budget needs a second look")
    try workspace.meetings.save(planning)
    try workspace.meetings.save(review)

    let both = try workspace.call("search_meetings", ["query": "CAFE BUDGET"]).text
    #expect(both.hasPrefix("Matches 1-2 of 2"))
    #expect(both.contains("Planning") && both.contains("Review"))

    let recent = try workspace.call("search_meetings", ["query": "café budget", "from": "2026-10-10T00:00:00Z"]).text
    #expect(recent.hasPrefix("Matches 1-1 of 1"))
    #expect(recent.contains("id \(planning.id.uuidString)"))
    let offset = try #require(continuation(in: recent))
    let context = try workspace.call("get_meeting", ["id": planning.id.uuidString, "offset": offset]).text
    #expect(context.contains("from line \(offset).\n\n[00:30] Speaker 1: We approved the café budget"))

    #expect(try workspace.call("search_meetings", ["query": "zebra"]).text == "No matches for \"zebra\".")
    #expect(try workspace.call("search_meetings", ["query": "  "]).isError)
}

@Test func searchPagesFiftyMatchesAtATime() throws {
    let workspace = Workspace()
    defer { try? FileManager.default.removeItem(at: workspace.root) }
    try workspace.connectedApps(true)
    try workspace.meetings.save(try meeting("Retro", at: "2026-10-14T09:00:00Z", segments: (0..<60).map { line("Ticket \($0) slipped", at: Double($0) * 5) }))

    let first = try workspace.call("search_meetings", ["query": "slipped"]).text
    #expect(first.hasPrefix("Matches 1-50 of 60"))
    #expect(first.contains("More matches remain. Call search_meetings again with offset 50"))
    let rest = try workspace.call("search_meetings", ["query": "slipped", "offset": 50]).text
    #expect(rest.hasPrefix("Matches 51-60 of 60"))
    #expect(rest.contains("Ticket 59 slipped") && !rest.contains("Ticket 0 slipped"))
}

@Test func unreadableMeetingFilesAreSkippedReportedAndNeverRewritten() throws {
    let workspace = Workspace()
    defer { try? FileManager.default.removeItem(at: workspace.root) }
    try workspace.connectedApps(true)
    let kept = try meeting("Design crit", at: "2026-10-14T09:00:00Z", notes: "Typography first")
    try workspace.meetings.save(kept)
    let directory = workspace.meetings.directory
    try Data("not json".utf8).write(to: directory.appendingPathComponent("broken.json"))
    try Data(#"{"version":2,"meeting":{"future":true}}"#.utf8).write(to: directory.appendingPathComponent("future.json"))
    func snapshot() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(atPath: directory.path).map { ($0, try Data(contentsOf: directory.appendingPathComponent($0))) })
    }
    let before = try snapshot()

    let list = try workspace.call("list_meetings")
    #expect(!list.isError && list.text.contains("Design crit"))
    #expect(list.text.contains("Skipped 2 meeting files BetterWispr could not read."))
    #expect(try workspace.call("search_meetings", ["query": "typography"]).text.contains("Skipped 2 meeting files"))
    #expect(try !workspace.call("get_meeting", ["id": kept.id.uuidString]).isError)
    #expect(try snapshot() == before)
}

@Test func protocolErrorsUseJSONRPCCodes() throws {
    let workspace = Workspace()
    func code(_ line: String) throws -> Int? { (try workspace.send(line)["error"] as? [String: Any])?["code"] as? Int }

    let malformed = try workspace.send(#"{"jsonrpc":"2.0","id":1,"method":"#)
    #expect(malformed["id"] is NSNull)
    #expect((malformed["error"] as? [String: Any])?["code"] as? Int == -32700)
    #expect(try code("[1,2]") == -32600)
    #expect(try code(#"{"id":4,"method":"ping"}"#) == -32600)
    let unknown = try workspace.send(#"{"jsonrpc":"2.0","id":3,"method":"resources/list"}"#)
    #expect(unknown["id"] as? Int == 3)
    #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32601)
    #expect(try code(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"delete_meeting"}}"#) == -32602)
}
