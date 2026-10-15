import Foundation

/// A voice the user named in a meeting, kept on this Mac to name the same voice in later meetings.
public struct KnownVoice: Codable, Equatable, Sendable {
    public var name: String
    public var meetingID: UUID
    public var participant: Int
    public var embedding: [Float]

    public init(name: String, meetingID: UUID, participant: Int, embedding: [Float]) {
        self.name = name
        self.meetingID = meetingID
        self.participant = participant
        self.embedding = embedding
    }
}

/// Remembered voices in one file; a file that fails to load is left for the caller to report, never overwritten.
public struct VoiceStore: Sendable {
    public let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? URL.applicationSupportDirectory.appendingPathComponent("BetterWispr/Voices.json")
    }

    private struct File: Codable {
        var version: Int
        var voices: [KnownVoice]
    }

    public func load() throws -> [KnownVoice] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        guard file.version == 1 else { throw StoreError.unsupportedVersion(file.version) }
        return file.voices
    }

    public func save(_ voices: [KnownVoice]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(File(version: 1, voices: voices)).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Replaces the voices remembered from one meeting, writing only on a change and never over a file that can't be read.
    public func replaceVoices(from meeting: UUID, with voices: [KnownVoice]) throws {
        let known = try load()
        guard known.filter({ $0.meetingID == meeting }) != voices else { return }
        try save(known.filter { $0.meetingID != meeting } + voices)
    }

    /// Deletes every remembered voice, including a file that couldn't be read.
    public func forget() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
