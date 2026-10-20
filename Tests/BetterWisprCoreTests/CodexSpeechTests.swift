import Foundation
import Testing
@testable import BetterWisprCore
@testable import BetterWispr

private struct CodexFixture {
    let root: URL
    let auth: URL
    let audio: URL
    let token = "test-\(UUID())"

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("betterwispr-codex-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        auth = root.appendingPathComponent("auth.json")
        audio = root.appendingPathComponent("private-recording.wav")
        try signIn()
        try SpeechAudio.wav(Array(repeating: 0.1, count: 1600)).write(to: audio)
    }

    func signIn(token: String? = nil, account: String? = "test-account") throws {
        var tokens = ["access_token": token ?? self.token]
        tokens["account_id"] = account
        try JSONSerialization.data(withJSONObject: ["auth_mode": "chatgpt", "tokens": tokens]).write(to: auth)
    }

    @MainActor func provider() -> CodexSpeechProvider {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CodexEndpointStub.self]
        return CodexSpeechProvider(configuration: config, credentials: { try CodexCredentials.load(file: auth) })
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Suite(.serialized)
@MainActor
struct CodexSpeechTests {
    @Test func preparationValidatesOnlyLocalSignInAndClearsFailedPreparation() async throws {
        let fixture = try CodexFixture()
        defer { fixture.remove() }
        let provider = fixture.provider()
        for download in [false, true] { try await provider.prepare(model: .codex, download: download) }
        #expect(await CodexEndpointStub.probe.requests(fixture.token).isEmpty)
        do {
            try await provider.prepare(model: SpeechModel.catalog[0], download: false)
            Issue.record("An unrelated model must fail preparation")
        } catch SpeechError.invalidModel {}
        do {
            _ = try await provider.transcribe(audioURL: fixture.audio, language: nil, vocabulary: [])
            Issue.record("Failed preparation must clear readiness")
        } catch SpeechError.notPrepared {}
        try FileManager.default.removeItem(at: fixture.auth)
        await #expect(throws: CodexSpeechError.signInRequired) { try await provider.prepare(model: .codex, download: false) }
        #expect(await CodexEndpointStub.probe.requests(fixture.token).isEmpty)
    }

    @Test func multipartUsesPinnedEndpointHeadersAndOnlyAudioAndNormalizedLanguage() async throws {
        let fixture = try CodexFixture()
        defer { fixture.remove() }
        let provider = fixture.provider()
        try await provider.prepare(model: .codex, download: false)
        #expect(try await provider.transcribe(audioURL: fixture.audio, language: "uk-UA", vocabulary: ["private-vocabulary"]) == "Hello")
        let captured = try #require(await CodexEndpointStub.probe.requests(fixture.token).first)
        #expect(captured.request.url?.absoluteString == "https://chatgpt.com/backend-api/transcribe")
        #expect(captured.request.httpMethod == "POST")
        #expect(captured.request.value(forHTTPHeaderField: "Authorization") == "Bearer \(fixture.token)")
        #expect(captured.request.value(forHTTPHeaderField: "originator") == "Codex Desktop")
        #expect(captured.request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "test-account")
        let agent = try #require(captured.request.value(forHTTPHeaderField: "User-Agent"))
        #expect(agent.hasPrefix("Codex Desktop/"))
        #if arch(arm64)
        #expect(agent.hasSuffix(" (macos; aarch64)"))
        #else
        #expect(agent.hasSuffix(" (macos; x86_64)"))
        #endif
        #expect(captured.request.timeoutInterval == 60)
        let body = String(decoding: captured.body, as: UTF8.self)
        #expect(body.contains("name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF"))
        #expect(body.contains("name=\"language\"\r\n\r\nuk\r\n"))
        for omitted in ["private-recording", fixture.root.path, "private-vocabulary", "name=\"model\"", "response_format", "prompt", "context"] {
            #expect(!body.contains(omitted))
        }
        let contentType = try #require(captured.request.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try #require(contentType.components(separatedBy: "boundary=").last)
        #expect(body.hasPrefix("--\(boundary)\r\n"))
        #expect(body.hasSuffix("\r\n--\(boundary)--\r\n"))
        let wave = try #require(captured.body.range(of: Data("RIFF".utf8)))
        #expect(Array(captured.body[wave.lowerBound + 22..<wave.lowerBound + 28]) == [1, 0, 128, 62, 0, 0])
    }

    @Test func transcriptionReadsFreshSignInBeforeConvertingAudioAndAutoOmitsLanguage() async throws {
        let fixture = try CodexFixture()
        defer { fixture.remove() }
        let provider = fixture.provider()
        try await provider.prepare(model: .codex, download: false)
        let rotated = "rotated-\(UUID())"
        try fixture.signIn(token: rotated, account: nil)
        _ = try await provider.transcribe(audioURL: fixture.audio, language: "auto", vocabulary: [])
        #expect(await CodexEndpointStub.probe.requests(fixture.token).isEmpty)
        let captured = try #require(await CodexEndpointStub.probe.requests(rotated).first)
        #expect(captured.request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil)
        #expect(!String(decoding: captured.body, as: UTF8.self).contains("name=\"language\""))
        try FileManager.default.removeItem(at: fixture.auth)
        await #expect(throws: CodexSpeechError.signInRequired) {
            try await provider.transcribe(audioURL: fixture.root.appendingPathComponent("missing.wav"), language: nil, vocabulary: [])
        }
        #expect(await CodexEndpointStub.probe.requests(rotated).count == 1)
    }

    @Test func authModesTokenHeadersAndMalformedFilesAreValidatedWithoutExposingContents() throws {
        for mode in [nil, "chatgpt", "chatgpt_auth_tokens"] as [String?] {
            var object: [String: Any] = ["tokens": ["access_token": "test-token"]]
            object["auth_mode"] = mode
            #expect(try CodexCredentials(data: JSONSerialization.data(withJSONObject: object)).accessToken == "test-token")
        }
        #expect(try credentials(#"{"authMode":"chatgpt","tokens":{"access_token":"test-token"}}"#).accountID == nil)
        #expect(try credentials(#"{"auth_mode":"chatgpt","authMode":"apikey","tokens":{"access_token":"test-token"}}"#).accessToken == "test-token")
        let invalid = [
            #"{"auth_mode":"apikey","authMode":"chatgpt","tokens":{"access_token":"secret"}}"#,
            #"{"auth_mode":"api_key","tokens":{"access_token":"secret"}}"#,
            #"{"OPENAI_API_KEY":"secret"}"#, #"{"tokens":{}}"#, #"{"tokens":{"access_token":42}}"#,
            #"{"tokens":{"access_token":""}}"#, #"{"tokens":{"access_token":"  "}}"#,
            #"{"tokens":{"access_token":"secret\r\nInjected: true"}}"#,
            #"{"tokens":{"access_token":"secret\u0000value"}}"#,
            #"{"tokens":{"access_token":"nonascii-ї"}}"#,
            #"{"tokens":{"access_token":"valid","account_id":"bad\naccount"}}"#,
            #"{"tokens":{"access_token":"valid","account_id":""}}"#, "secret-invalid-json",
        ]
        for json in invalid {
            #expect(throws: CodexSpeechError.signInRequired) { try credentials(json) }
        }
        #expect(!CodexSpeechError.signInRequired.localizedDescription.contains("secret"))
    }

    @Test func jwtAccountFallbackIsOptionalAndExplicitAccountTakesPrecedence() throws {
        func token(_ account: String) throws -> String {
            let payload = try JSONSerialization.data(withJSONObject: ["https://api.openai.com/auth": ["chatgpt_account_id": account]])
                .base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            return "header.\(payload).signature"
        }
        let jwt = try token("jwt-account")
        #expect(try credentials(#"{"tokens":{"access_token":"\#(jwt)"}}"#).accountID == "jwt-account")
        #expect(try credentials(#"{"tokens":{"access_token":"\#(jwt)","account_id":"explicit-account"}}"#).accountID == "explicit-account")
        #expect(try credentials(#"{"tokens":{"access_token":"opaque-token"}}"#).accountID == nil)
        let injected = try token("bad\r\naccount")
        #expect(throws: CodexSpeechError.signInRequired) { try credentials(#"{"tokens":{"access_token":"\#(injected)"}}"#) }
    }

    @Test func authLocationHonorsCodexHomeAndBoundsFileReads() throws {
        let fixture = try CodexFixture()
        defer { fixture.remove() }
        let defaultHome = fixture.root.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: defaultHome, withIntermediateDirectories: false)
        try FileManager.default.copyItem(at: fixture.auth, to: defaultHome.appendingPathComponent("auth.json"))
        #expect(try CodexCredentials.load(environment: [:], home: fixture.root).accessToken == fixture.token)
        #expect(try CodexCredentials.load(environment: ["CODEX_HOME": fixture.root.path], home: URL(fileURLWithPath: "/missing")).accessToken == fixture.token)
        #expect(throws: CodexSpeechError.signInRequired) {
            try CodexCredentials.load(environment: ["CODEX_HOME": fixture.root.appendingPathComponent("missing").path], home: fixture.root)
        }
        try Data(repeating: 120, count: 1_048_577).write(to: fixture.auth)
        #expect(throws: CodexSpeechError.signInRequired) { try CodexCredentials.load(file: fixture.auth) }
        #expect(throws: CodexSpeechError.signInRequired) { try CodexCredentials.load(file: fixture.root) }
    }

    @Test func httpAndTransportFailuresHaveOnlySafeActionableMessages() async throws {
        let cases: [(Int, CodexSpeechError)] = [(401, .signInRequired), (403, .accessDenied), (429, .quotaReached), (500, .http(500)), (307, .http(307))]
        for (status, expected) in cases {
            let fixture = try CodexFixture()
            defer { fixture.remove() }
            await CodexEndpointStub.probe.set(fixture.token, [.response(status, "secret transcript, token and account")])
            let provider = fixture.provider()
            try await provider.prepare(model: .codex, download: false)
            await #expect(throws: expected) { try await provider.transcribe(audioURL: fixture.audio, language: nil, vocabulary: []) }
            #expect(!expected.localizedDescription.contains("secret"))
        }
        for (code, expected) in [(URLError.timedOut, CodexSpeechError.timedOut), (.notConnectedToInternet, .connectionFailed)] {
            let fixture = try CodexFixture()
            defer { fixture.remove() }
            await CodexEndpointStub.probe.set(fixture.token, [.failure(code)])
            let provider = fixture.provider()
            try await provider.prepare(model: .codex, download: false)
            await #expect(throws: expected) { try await provider.transcribe(audioURL: fixture.audio, language: nil, vocabulary: []) }
        }
    }

    @Test func responseRequiresTextAndAcceptsEmptySpeech() async throws {
        for json in [#"{"text":"  "}"#, #"{"text":" Привіт "}"#, "{}", #"{"text":null}"#, #"{"text":4}"#, "not json"] {
            let fixture = try CodexFixture()
            defer { fixture.remove() }
            await CodexEndpointStub.probe.set(fixture.token, [.response(200, json)])
            let provider = fixture.provider()
            try await provider.prepare(model: .codex, download: false)
            if json == #"{"text":"  "}"# {
                #expect(try await provider.transcribe(audioURL: fixture.audio, language: nil, vocabulary: []) == "")
            } else if json == #"{"text":" Привіт "}"# {
                #expect(try await provider.transcribe(audioURL: fixture.audio, language: nil, vocabulary: []) == "Привіт")
            } else {
                await #expect(throws: CodexSpeechError.invalidResponse) { try await provider.transcribe(audioURL: fixture.audio, language: nil, vocabulary: []) }
            }
        }
        #expect(throws: CodexSpeechError.invalidResponse) { try CodexSpeechProvider.transcript(Data(repeating: 120, count: 2_000_001), status: 200) }
    }

    @Test(arguments: [true, false])
    func cancellationStopsNativeRequestAndAllowsNextOperation(_ cancelProvider: Bool) async throws {
        let fixture = try CodexFixture()
        defer { fixture.remove() }
        await CodexEndpointStub.probe.set(fixture.token, [.wait])
        let provider = fixture.provider()
        try await provider.prepare(model: .codex, download: false)
        let task = Task { try await provider.transcribe(audioURL: fixture.audio, language: nil, vocabulary: []) }
        try await waitForRequests(fixture.token, count: 1)
        if cancelProvider { provider.cancel() } else { task.cancel() }
        await #expect(throws: CancellationError.self) { try await task.value }
        try await waitForStop(fixture.token)
        #expect(try await provider.transcribe(audioURL: fixture.audio, language: nil, vocabulary: []) == "Hello")
    }

    @Test func sessionsAreIndependentAndRejectConcurrentPrepareAndTranscribe() async throws {
        let first = try CodexFixture(), second = try CodexFixture()
        defer { first.remove(); second.remove() }
        await CodexEndpointStub.probe.set(first.token, [.wait])
        let one = first.provider(), two = second.provider()
        try await one.prepare(model: .codex, download: false)
        try await two.prepare(model: .codex, download: false)
        let task = Task { try await one.transcribe(audioURL: first.audio, language: nil, vocabulary: []) }
        try await waitForRequests(first.token, count: 1)
        do {
            try await one.prepare(model: .codex, download: false)
            Issue.record("A busy provider must reject preparation")
        } catch SpeechError.busy {}
        do {
            _ = try await one.transcribe(audioURL: first.audio, language: nil, vocabulary: [])
            Issue.record("A busy provider must reject a second transcription")
        } catch SpeechError.busy {}
        #expect(try await two.transcribe(audioURL: second.audio, language: nil, vocabulary: []) == "Hello")
        one.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func lateSuccessAndPrecancelNeverReturnTextOrUploadAudio() async throws {
        let fixture = try CodexFixture()
        defer { fixture.remove() }
        let provider = fixture.provider()
        try await provider.prepare(model: .codex, download: false)
        let task = Task { try await provider.transcribe(audioURL: fixture.audio, language: nil, vocabulary: []) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await CodexEndpointStub.probe.requests(fixture.token).isEmpty)
        provider.onProgress = { _ in provider.cancel() }
        await #expect(throws: CancellationError.self) { try await provider.transcribe(audioURL: fixture.audio, language: nil, vocabulary: []) }
        #expect(await CodexEndpointStub.probe.requests(fixture.token).count == 1)
    }

    @Test func chunksUploadInOrderAndFailureNeverReturnsPartialTranscript() async throws {
        for fails in [false, true] {
            let fixture = try CodexFixture()
            defer { fixture.remove() }
            let samples = Array(repeating: Float(0.1), count: 125 * 16_000) + Array(repeating: Float(0.2), count: 16_000)
            try SpeechAudio.wav(samples).write(to: fixture.audio)
            await CodexEndpointStub.probe.set(fixture.token, [.response(200, #"{"text":"first"}"#), .response(fails ? 500 : 200, #"{"text":"second"}"#)])
            let provider = fixture.provider()
            var progress: [Double] = []
            provider.onProgress = { progress.append($0) }
            try await provider.prepare(model: .codex, download: false)
            if fails {
                await #expect(throws: CodexSpeechError.http(500)) { try await provider.transcribe(audioURL: fixture.audio, language: nil, vocabulary: []) }
                #expect(progress == [0.5])
            } else {
                #expect(try await provider.transcribe(audioURL: fixture.audio, language: nil, vocabulary: []) == "first second")
                #expect(progress == [0.5, 1])
            }
            let requests = await CodexEndpointStub.probe.requests(fixture.token)
            #expect(requests.count == 2)
            #expect(requests[0].body.count > 3_900_000)
            #expect(requests[1].body.count < 33_000)
        }
    }

    @Test func invalidLanguageNeverUploadsAndSignInCannotTriggerDownloadsOrWarmup() async throws {
        let fixture = try CodexFixture()
        defer { fixture.remove() }
        let provider = fixture.provider()
        try await provider.prepare(model: .codex, download: false)
        await #expect(throws: CodexSpeechError.invalidLanguage) {
            try await provider.transcribe(audioURL: fixture.audio, language: "en\r\nInjected", vocabulary: [])
        }
        #expect(await CodexEndpointStub.probe.requests(fixture.token).isEmpty)
        let model = SpeechModel.codex
        #expect(model.id == "codex")
        #expect(model.name == "Codex · Subscription")
        #expect(!SpeechModel.catalog.contains(model))
        #expect(SpeechModel.catalog.allSatisfy { $0.processingLocation.isOnDevice })
        #expect(!model.supportsSyntheticWarmUp)
        #expect(!model.requiresModelDownload)
        #expect(model.requiresPreparationBeforeRecording)
        #expect(!model.processingLocation.isOnDevice)
        #expect(AppSettings().selectedModelID == "apple")
        let folder = fixture.root.appendingPathComponent("store")
        let app = AppModel(store: LocalStore(directory: folder), startsServices: false)
        app.selectModel(model)
        #expect(app.selectedModel == model)
        #expect(app.isModelInstalled(model))
        #expect(!app.isSpeechModelLoaded)
        app.installModel(model)
        #expect(!app.isInstalling)
        #expect(AppModel(store: LocalStore(directory: folder), startsServices: false).selectedModel == model)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(app.settings)).selectedModelID == "codex")
    }

    private func credentials(_ json: String) throws -> CodexCredentials { try CodexCredentials(data: Data(json.utf8)) }

    private func waitForRequests(_ token: String, count: Int) async throws {
        for _ in 0..<300 {
            if await CodexEndpointStub.probe.requests(token).count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The native transcription request did not start")
        throw URLError(.timedOut)
    }

    private func waitForStop(_ token: String) async throws {
        for _ in 0..<300 {
            if await CodexEndpointStub.probe.stopped.contains(token) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Cancellation did not stop the native request")
        throw URLError(.timedOut)
    }
}

private actor CodexRequestProbe {
    struct Captured: Sendable { let request: URLRequest; let body: Data }
    enum Reply: Sendable { case response(Int, String), failure(URLError.Code), wait }
    private var captured: [String: [Captured]] = [:]
    private var replies: [String: [Reply]] = [:]
    var stopped: Set<String> = []

    func set(_ token: String, _ replies: [Reply]) { self.replies[token] = replies }
    func requests(_ token: String) -> [Captured] { captured[token] ?? [] }
    func stop(_ token: String) { stopped.insert(token) }
    func start(_ request: URLRequest, body: Data) -> Reply {
        let token = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst(7))
        captured[token, default: []].append(Captured(request: request, body: body))
        guard var remaining = replies[token], !remaining.isEmpty else { return .response(200, #"{"text":"Hello"}"#) }
        let reply = remaining.removeFirst()
        replies[token] = remaining
        return reply
    }
}

// URLSession calls this subclass on its threads. It has no mutable instance state;
// its request history and response plans belong to the probe actor.
private final class CodexEndpointStub: URLProtocol, @unchecked Sendable {
    static let probe = CodexRequestProbe()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 8192)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let capturedBody = body
        Task {
            switch await Self.probe.start(request, body: capturedBody) {
            case .wait: return
            case .failure(let code):
                client?.urlProtocol(self, didFailWithError: URLError(code, userInfo: [NSLocalizedDescriptionKey: "secret token and transcript"]))
            case .response(let status, let json):
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(json.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }
    override func stopLoading() {
        let token = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst(7))
        Task { await Self.probe.stop(token) }
    }
}
