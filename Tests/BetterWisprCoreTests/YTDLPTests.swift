import Foundation
import Testing
@testable import BetterWisprCore

@Test func mediaLinksMustBeWebAddresses() throws {
    #expect(try MediaLink("  https://www.youtube.com/watch?v=1aA1WGON49E \n").url.absoluteString == "https://www.youtube.com/watch?v=1aA1WGON49E")
    #expect(try MediaLink("https://youtu.be/1aA1WGON49E").url.host == "youtu.be")
    #expect(try MediaLink("HTTP://example.com/talk").url.host == "example.com")
    for text in ["", "   ", "file:///etc/passwd", "javascript:alert(1)", "-o/tmp/x https://youtu.be/a", "--exec=open https://youtu.be/a",
                 "https://", "www.youtube.com/watch?v=1aA1WGON49E", "ftp://example.com/talk.mp3"] {
        #expect(throws: YTDLPError.invalidLink, "\(text)") { try MediaLink(text) }
    }
}

@Test func ytDLPInstallsOnlyTheBinaryMatchingItsPublishedChecksum() throws {
    let sums = """
    0000000000000000000000000000000000000000000000000000000000000000  yt-dlp
    BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD  yt-dlp_macos
    1111111111111111111111111111111111111111111111111111111111111111  yt-dlp_macos.zip
    """
    try YTDLP.verify(Data("abc".utf8), sums: sums)
    #expect(throws: YTDLPError.unverified) { try YTDLP.verify(Data("abd".utf8), sums: sums) }
    #expect(throws: YTDLPError.unverified) { try YTDLP.verify(Data("abc".utf8), sums: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  yt-dlp") }
}

@Test func ytDLPArgumentsEndTheOptionsBeforeTheLink() throws {
    let link = try MediaLink("https://www.youtube.com/watch?v=1aA1WGON49E&list=PL1")
    let folder = URL(fileURLWithPath: "/tmp/betterwispr-media-test")
    let arguments = YTDLP.arguments(for: link, into: folder, runtime: URL(fileURLWithPath: "/opt/homebrew/bin/node"))

    #expect(arguments.suffix(2) == ["--", "https://www.youtube.com/watch?v=1aA1WGON49E&list=PL1"])
    #expect(arguments.filter { $0 == "--" }.count == 1)
    #expect(arguments.starts(with: ["--no-config", "--no-playlist"]))
    #expect(arguments.contains("/tmp/betterwispr-media-test/media.%(ext)s"))
    #expect(arguments.contains("node:/opt/homebrew/bin/node"))
    #expect(!YTDLP.arguments(for: link, into: folder, runtime: nil).contains("--js-runtimes"))
}

@Test func ytDLPReportsItsProgressAndItsLastError() {
    #expect(YTDLP.progress(in: "[youtube] x: Downloading webpage\nbetterwispr-progress 25 100 NA\nbetterwispr-progress 50 NA 200\n") == 0.25)
    #expect(YTDLP.progress(in: "betterwispr-progress 50 NA NA\n") == nil)
    let errors = "WARNING: [youtube] No supported JavaScript runtime\nERROR: first\nERROR: [youtube] abc: Video unavailable\n"
    #expect(YTDLP.failure(errors, status: 1, runtime: URL(fileURLWithPath: "/opt/homebrew/bin/deno")) == .download("[youtube] abc: Video unavailable"))
    #expect(YTDLP.failure(errors, status: 1, runtime: nil).localizedDescription.contains("brew install deno"))
}

@MainActor
private func fakeYTDLP(_ behaviour: String) throws -> (executable: URL, seen: URL) {
    let folder = FileManager.default.temporaryDirectory.appending(path: "betterwispr-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let executable = folder.appending(path: "yt-dlp")
    try """
    #!/bin/sh
    while [ $# -gt 0 ]; do
      case "$1" in
        -o) out="$2"; shift ;;
        --print-to-file) title="$3"; shift 2 ;;
      esac
      shift
    done
    dir=$(dirname "$out")
    echo "$dir" > "$(dirname "$0")/seen"
    \(behaviour)
    """.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return (executable, folder.appending(path: "seen"))
}

@MainActor
private func folder(seenBy fake: (executable: URL, seen: URL)) throws -> String {
    try String(contentsOf: fake.seen, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
}

@MainActor
@Test func ytDLPDownloadsIntoAPrivateFolderItDeletesAfterSuccessErrorAndCancel() async throws {
    let link = try MediaLink("https://www.youtube.com/watch?v=1aA1WGON49E")
    let success = try fakeYTDLP("""
    echo 'betterwispr-progress 1 2 NA'
    sleep 0.5
    echo 'A talk' > "$title"
    printf 'audio' > "$dir/media.m4a"
    """)
    defer { try? FileManager.default.removeItem(at: success.executable.deletingLastPathComponent()) }
    var fractions: [Double?] = []
    let (title, contents, permissions) = try await YTDLP.download(link, using: success.executable, progress: { fractions.append($0) }) { audio, title in
        (title, try String(contentsOf: audio, encoding: .utf8),
         try FileManager.default.attributesOfItem(atPath: audio.deletingLastPathComponent().path)[.posixPermissions] as? Int)
    }
    #expect(title == "A talk" && contents == "audio" && permissions == 0o700)
    #expect(fractions.contains(0.5))
    #expect(try folder(seenBy: success).contains("betterwispr-media-"))
    #expect(!FileManager.default.fileExists(atPath: try folder(seenBy: success)))

    let failing = try fakeYTDLP("echo 'ERROR: [youtube] abc: Video unavailable' >&2; exit 1")
    defer { try? FileManager.default.removeItem(at: failing.executable.deletingLastPathComponent()) }
    let error = await #expect(throws: YTDLPError.self) { try await YTDLP.download(link, using: failing.executable) { _, _ in } }
    #expect(error?.localizedDescription.contains("[youtube] abc: Video unavailable") == true)
    #expect(!FileManager.default.fileExists(atPath: try folder(seenBy: failing)))

    let hanging = try fakeYTDLP("exec sleep 60")
    defer { try? FileManager.default.removeItem(at: hanging.executable.deletingLastPathComponent()) }
    let job = Task { try await YTDLP.download(link, using: hanging.executable) { _, _ in } }
    try await Task.sleep(for: .milliseconds(500))
    #expect(YTDLP.running?.isRunning == true)
    job.cancel()
    await #expect(throws: CancellationError.self) { try await job.value }
    #expect(!FileManager.default.fileExists(atPath: try folder(seenBy: hanging)))
    #expect(YTDLP.running == nil)

    await #expect(throws: YTDLPError.notInstalled) { try await YTDLP.download(link, using: nil) { _, _ in } }
}
