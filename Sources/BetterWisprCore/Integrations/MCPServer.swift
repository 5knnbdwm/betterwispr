import Foundation

/// A read-only MCP server over standard input and output that shares saved meetings while Connected apps is on.
public struct MCPServer: Sendable {
    public static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    static let offMessage = "Connected apps is off. Turn it on in BetterWispr Settings > Connected apps, then try again."

    let meetings: MeetingStore
    let settings: LocalStore

    public init(meetings: MeetingStore = MeetingStore(), settings: LocalStore = LocalStore()) {
        self.meetings = meetings
        self.settings = settings
    }

    /// Answers newline-delimited JSON-RPC messages from standard input until it closes.
    public func serveStandardIO() {
        while let line = readLine() {
            guard let reply = reply(to: line) else { continue }
            FileHandle.standardOutput.write(Data((reply + "\n").utf8))
        }
    }

    /// The single-line JSON-RPC reply to one message, or nil when the message needs none.
    public func reply(to line: String) -> String? {
        guard !line.allSatisfy(\.isWhitespace) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) else {
            return encode(id: NSNull(), .failure(RPCError(code: -32700, message: "Parse error")))
        }
        guard let message = object as? [String: Any], message["jsonrpc"] as? String == "2.0", let method = message["method"] as? String else {
            return encode(id: (object as? [String: Any])?["id"] ?? NSNull(), .failure(RPCError(code: -32600, message: "Invalid request")))
        }
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        return switch method {
        case "initialize": encode(id: id, .success(initialize(params)))
        case "ping": encode(id: id, .success([:]))
        case "tools/list": encode(id: id, .success(["tools": MeetingTool.allCases.map(\.definition)]))
        case "tools/call": encode(id: id, call(params))
        default: encode(id: id, .failure(RPCError(code: -32601, message: "Method not found: \(method)")))
        }
    }

    private func initialize(_ params: [String: Any]) -> [String: Any] {
        let requested = params["protocolVersion"] as? String ?? ""
        return [
            "protocolVersion": Self.protocolVersions.contains(requested) ? requested : Self.protocolVersions[0],
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": [
                "name": "betterwispr",
                "title": "BetterWispr",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
            ],
            "instructions": "Read-only access to the meeting notes saved in BetterWispr on this Mac. Find a meeting with list_meetings or search_meetings, then read it with get_meeting.",
        ]
    }

    private func call(_ params: [String: Any]) -> Result<[String: Any], RPCError> {
        guard let name = params["name"] as? String, let tool = MeetingTool(rawValue: name) else {
            return .failure(RPCError(code: -32602, message: "Unknown tool: \(params["name"] as? String ?? "none")"))
        }
        func content(_ text: String, isError: Bool) -> Result<[String: Any], RPCError> {
            .success(["content": [["type": "text", "text": text]], "isError": isError])
        }
        guard (try? settings.load().settings.mcpServer) == true else { return content(Self.offMessage, isError: true) }
        do throws(ToolFailure) {
            return content(try tool.run(ToolArguments(values: params["arguments"] as? [String: Any] ?? [:]), store: meetings), isError: false)
        } catch {
            return content(error.message, isError: true)
        }
    }

    private func encode(id: Any, _ outcome: Result<[String: Any], RPCError>) -> String {
        var reply: [String: Any] = ["jsonrpc": "2.0", "id": id]
        switch outcome {
        case .success(let result): reply["result"] = result
        case .failure(let error): reply["error"] = ["code": error.code, "message": error.message]
        }
        let data = try! JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}

private struct RPCError: Error {
    let code: Int
    let message: String
}

private struct ToolFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

private struct ToolArguments {
    let values: [String: Any]

    func string(_ key: String) throws(ToolFailure) -> String? {
        guard let value = values[key], !(value is NSNull) else { return nil }
        guard let text = value as? String else { throw ToolFailure("\(key) must be a string.") }
        return text
    }

    func offset() throws(ToolFailure) -> Int {
        guard let value = values["offset"], !(value is NSNull) else { return 0 }
        guard let offset = value as? Int, offset >= 0 else { throw ToolFailure("offset must be a whole number, 0 or more.") }
        return offset
    }

    func startFilter() throws(ToolFailure) -> (Date) -> Bool {
        let earliest = try bound("from", asExclusiveEnd: false)
        let end = try bound("to", asExclusiveEnd: true)
        return { start in (earliest.map { start >= $0 } ?? true) && (end.map { start < $0 } ?? true) }
    }

    private func bound(_ key: String, asExclusiveEnd: Bool) throws(ToolFailure) -> Date? {
        guard let text = try string(key) else { return nil }
        if let moment = ISO8601DateFormatter().date(from: text) { return asExclusiveEnd ? moment + 1 : moment }
        let localDay = ISO8601DateFormatter()
        localDay.formatOptions = [.withFullDate]
        localDay.timeZone = .current
        guard let midnight = localDay.date(from: text) else {
            throw ToolFailure("\(key) must be a date like 2026-10-14 or a date-time like 2026-10-14T09:00:00Z.")
        }
        return asExclusiveEnd ? Calendar.current.date(byAdding: .day, value: 1, to: midnight) : midnight
    }
}

private enum MeetingTool: String, CaseIterable {
    case list = "list_meetings", get = "get_meeting", search = "search_meetings"

    static let pageSize = 50
    static let characterLimit = 30_000

    var definition: [String: Any] {
        let dates: [String: Any] = [
            "from": ["type": "string", "description": "Earliest meeting start to include, as YYYY-MM-DD in local time or an ISO 8601 date-time."],
            "to": ["type": "string", "description": "Latest meeting start to include, as YYYY-MM-DD (the whole day counts) or an ISO 8601 date-time."],
        ]
        let (title, description, properties, required): (String, String, [String: Any], [String]) = switch self {
        case .list: (
            "List meetings",
            "Lists saved meetings newest first with id, title, start date, duration, calendar attendees and speakers. Returns up to \(Self.pageSize) at a time; the reply says which offset continues the list.",
            dates.merging(["offset": Self.offsetSchema("How many matching meetings to skip.")]) { $1 },
            []
        )
        case .get: (
            "Get meeting",
            "Returns one meeting's summary, key points, decisions, action items, the user's own notes and the transcript with speaker names and timestamps. Long meetings come in parts; the reply says which offset continues it.",
            ["id": ["type": "string", "description": "The meeting id from list_meetings or search_meetings."],
             "offset": Self.offsetSchema("The line to start from, as given by a previous reply or a search match.")],
            ["id"]
        )
        case .search: (
            "Search meetings",
            "Finds lines in saved meetings that contain the query, ignoring case and accents. Searches titles, attendees, summaries, action items, the user's notes and transcripts. Returns up to \(Self.pageSize) matches at a time; the reply says which offset continues the list.",
            dates.merging([
                "query": ["type": "string", "description": "Text to find, matched as a whole phrase."],
                "offset": Self.offsetSchema("How many matches to skip."),
            ]) { $1 },
            ["query"]
        )
        }
        return [
            "name": rawValue,
            "title": title,
            "description": description,
            "inputSchema": ["type": "object", "properties": properties, "required": required],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ]
    }

    private static func offsetSchema(_ description: String) -> [String: Any] {
        ["type": "integer", "minimum": 0, "description": description]
    }

    func run(_ arguments: ToolArguments, store: MeetingStore) throws(ToolFailure) -> String {
        let (meetings, unreadable) = store.load()
        let skipped = unreadable.isEmpty ? [] : ["Skipped \(unreadable.count) meeting file\(unreadable.count == 1 ? "" : "s") BetterWispr could not read."]
        switch self {
        case .list:
            let inRange = try arguments.startFilter()
            let offset = try arguments.offset()
            let matching = meetings.filter { inRange($0.createdAt) }
            let (shown, next) = Self.page(matching.map(Self.header), from: offset, atMost: Self.pageSize)
            let heading = matching.isEmpty ? "No meetings found."
                : shown.isEmpty ? "Offset \(offset) is past the last of \(matching.count) meetings."
                : "Meetings \(offset + 1)-\(offset + shown.count) of \(matching.count), newest first."
            let more = next.map { ["More meetings remain. Call list_meetings again with offset \($0) and the same from and to."] } ?? []
            return ([heading] + shown + more + skipped).joined(separator: "\n\n")
        case .get:
            guard let text = try arguments.string("id"), let id = UUID(uuidString: text.trimmingCharacters(in: .whitespaces)) else {
                throw ToolFailure("id must be a meeting id from list_meetings or search_meetings.")
            }
            guard let meeting = meetings.first(where: { $0.id == id }) else {
                throw ToolFailure("No saved meeting has id \(id.uuidString). Find ids with list_meetings or search_meetings.")
            }
            let offset = try arguments.offset()
            let lines = Self.document(meeting)
            guard offset < lines.count else { throw ToolFailure("offset \(offset) is past the end of this meeting, which has \(lines.count) lines.") }
            let (shown, next) = Self.page(lines, from: offset, atMost: .max)
            let resumed = offset > 0 ? ["Meeting \(id.uuidString), from line \(offset).", ""] : []
            let more = next.map { ["", "This meeting continues. Call get_meeting again with id \(id.uuidString) and offset \($0)."] } ?? []
            return (resumed + shown + more).joined(separator: "\n")
        case .search:
            guard let query = try arguments.string("query")?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
                throw ToolFailure("query must be the text to find.")
            }
            let inRange = try arguments.startFilter()
            let offset = try arguments.offset()
            let matches = meetings.filter { inRange($0.createdAt) }.flatMap { meeting in
                let source = "\(Meeting.oneLine(meeting.displayTitle)), \(Self.stamp(meeting.createdAt)), id \(meeting.id.uuidString)"
                return Self.document(meeting).enumerated().filter { _, line in
                    !line.hasPrefix("#") && line.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }.map { line, text in "\(source), offset \(line)\n\(text)" }
            }
            let (shown, next) = Self.page(matches, from: offset, atMost: Self.pageSize)
            let heading = matches.isEmpty ? "No matches for \"\(query)\"."
                : shown.isEmpty ? "Offset \(offset) is past the last of \(matches.count) matches."
                : "Matches \(offset + 1)-\(offset + shown.count) of \(matches.count) for \"\(query)\". Call get_meeting with a match's id and offset to read on from it."
            let more = next.map { ["More matches remain. Call search_meetings again with offset \($0) and the same query, from and to."] } ?? []
            return ([heading] + shown + more + skipped).joined(separator: "\n\n")
        }
    }

    private static func page(_ entries: [String], from offset: Int, atMost count: Int) -> (shown: ArraySlice<String>, next: Int?) {
        let start = min(offset, entries.count)
        var end = start
        var size = 0
        while end < entries.count, end - start < count {
            let isFirst = end == start
            guard isFirst || size + entries[end].count <= characterLimit else { break }
            size += entries[end].count + 1
            end += 1
        }
        return (entries[start..<end], end < entries.count ? end : nil)
    }

    private static func header(_ meeting: Meeting) -> String {
        let seconds = max(0, Int(meeting.duration.rounded()))
        let speakers = meeting.participants.map { MeetingSegment.label(of: $0, names: meeting.participantNames) }
        return [
            "id: \(meeting.id.uuidString)",
            "title: \(Meeting.oneLine(meeting.displayTitle))",
            "date: \(stamp(meeting.createdAt))",
            "duration: " + String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60),
            meeting.attendees.flatMap { $0.isEmpty ? nil : "attendees: " + $0.map(Meeting.oneLine).joined(separator: ", ") },
            speakers.isEmpty ? nil : "speakers: " + speakers.joined(separator: ", "),
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private static func document(_ meeting: Meeting) -> [String] {
        (header(meeting) + "\n\n" + meeting.markdown).components(separatedBy: "\n")
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
