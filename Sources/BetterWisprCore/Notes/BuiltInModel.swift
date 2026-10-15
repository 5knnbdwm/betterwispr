import CryptoKit
import Foundation
import WhisperKit

/// The pinned Qwen3.5 2B file BetterWispr downloads on request and runs in process with llama.cpp.
public enum BuiltInModel {
    public static let displayName = "Qwen3.5 2B"
    public static let sizeLabel = "1.28 GB"
    static let repo = "unsloth/Qwen3.5-2B-GGUF"
    static let revision = "f6d5376be1edb4d416d56da11e5397a961aca8ae"
    static let fileName = "Qwen3.5-2B-Q4_K_M.gguf"
    static let pinned = PinnedFile(byteCount: 1_280_835_840, sha256: "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223")
    static let marker = ".betterwispr-installed"

    public static var directory: URL {
        WhisperKitProvider.defaultModelsDirectory.appending(path: "models/\(repo)", directoryHint: .isDirectory)
    }

    public static var fileURL: URL { directory.appending(path: fileName) }

    static var installedStamp: String { "\(revision) \(pinned.sha256)" }

    /// True only when the marker written after verification names this pin and the file still has its pinned size; never reads the whole file.
    public static func isInstalled(at directory: URL = directory) -> Bool {
        (try? String(contentsOf: directory.appending(path: marker), encoding: .utf8)) == installedStamp
            && pinned.matchesSize(of: directory.appending(path: fileName))
    }

    /// Downloads the pinned file after an explicit installation action, checks its size and SHA-256, loads it once and only then writes the marker; any failure deletes the download.
    public static func install(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard !isInstalled() else { return }
        let base = WhisperKitProvider.defaultModelsDirectory
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: directory.appending(path: marker))
        let downloader = ModelDownloader(config: ModelDownloadConfig(downloadBase: base.path, modelRepo: repo, revision: revision))
        do {
            do {
                _ = try await downloader.resolveRepo(patterns: [fileName], downloadBase: base, download: true) {
                    progress?($0.fractionCompleted)
                }
            } catch {
                throw WhisperKitProvider.readableDownloadError(error)
            }
            try Task.checkCancellation()
            try pinned.verify(fileURL)
            let engine = LlamaEngine { try LlamaWeights(contentsOf: fileURL) }
            defer { engine.shutdown() }
            try await engine.verify(grammar: NotesDraft.grammar)
            try Task.checkCancellation()
            try Data(installedStamp.utf8).write(to: directory.appending(path: marker), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// Frees the shared engine's weights, then deletes the model; removing twice is harmless.
    public static func remove() async throws {
        await LlamaEngine.shared.unload()
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}

/// A download pinned by exact size and SHA-256.
struct PinnedFile: Sendable {
    let byteCount: Int
    let sha256: String

    /// Compares only the size, so availability never reads 1.3 GB.
    func matchesSize(of url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) == byteCount
    }

    /// Streams the file through SHA-256 in 8 MB reads, each freed by its own autorelease pool, stopping when the task is cancelled.
    func verify(_ url: URL) throws {
        guard matchesSize(of: url) else { throw BuiltInModelError.integrity }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while try autoreleasepool(invoking: {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw BuiltInModelError.integrity }
    }
}

public enum BuiltInModelError: LocalizedError {
    case integrity

    public var errorDescription: String? {
        "The download didn’t match the built-in model’s size and checksum. Try again."
    }
}

/// The built-in backend behind `NotesLanguageModel`; polish and review use the interactive lane, notes and Test the background one.
struct BuiltInNotesModel: NotesLanguageModel {
    let instructions: String
    let lane: LlamaEngine.Lane
    var engine = LlamaEngine.shared

    func respond(to prompt: String) async throws -> String {
        try await engine.complete(ChatPrompt(system: instructions, user: prompt), lane: lane)
    }

    func draft(_ prompt: String) async throws -> NotesDraft {
        let reply = try await engine.complete(ChatPrompt(system: instructions, user: "\(prompt)\n\n\(NotesDraft.fields)"), lane: lane, grammar: NotesDraft.grammar)
        var draft = try NotesDraft.decode(reply)
        draft.generatedWith = "Built-in · \(BuiltInModel.displayName)"
        return draft
    }
}

extension NotesDraft {
    /// GBNF for exactly the five fields `decode` reads, so the built-in model cannot reply with prose, fences or nested objects.
    static let grammar = #"""
        root ::= "{" ws "\"title\":" ws string "," ws "\"overview\":" ws string "," ws "\"keyPoints\":" ws list "," ws "\"decisions\":" ws list "," ws "\"actionItems\":" ws list ws "}"
        list ::= "[" ws ( string ( "," ws string )* )? ws "]"
        string ::= "\"" char* "\""
        char ::= [^"\\\x7F\x00-\x1F] | "\\" ( ["\\/bfnrt] | "u" [0-9a-fA-F]{4} )
        ws ::= [ \t\n]{0,8}
        """#
}
