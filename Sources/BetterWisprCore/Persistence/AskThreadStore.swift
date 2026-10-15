import Foundation

/// Saves the questions asked about all meetings, which belong to no single meeting file.
public struct AskThreadStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    private struct File: Codable {
        var version: Int
        var exchanges: [AskExchange]
    }

    /// Returns no exchanges when nothing was saved yet; throws for a file it can't read so the caller leaves it alone.
    public func load() throws -> [AskExchange] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        guard file.version == 1 else { throw StoreError.unsupportedVersion(file.version) }
        return file.exchanges
    }

    public func save(_ exchanges: [AskExchange]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(File(version: 1, exchanges: exchanges)).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
