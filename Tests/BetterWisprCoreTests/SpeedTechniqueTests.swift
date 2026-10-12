import AVFoundation
import Foundation
import Testing
@testable import BetterWisprCore

@Test func lowLatencyFieldsOnlyTargetHostsAndModelsThatAcceptThem() {
    let cases: [(host: String?, model: String, fields: [String: Any])] = [
        ("api.openai.com", "gpt-5.4-mini", ["reasoning_effort": "none", "temperature": 0.3]),
        ("API.OpenAI.com", "gpt-6-sol", ["reasoning_effort": "none", "temperature": 0.3]),
        ("api.groq.com", "openai/gpt-oss-20b", ["reasoning_effort": "low", "include_reasoning": false, "temperature": 0.3]),
        ("api.cerebras.ai", "gpt-oss-120b", ["reasoning_effort": "low", "reasoning_format": "hidden", "temperature": 0.3]),
        ("api.groq.com", "qwen/qwen3.8-27b", ["reasoning_effort": "none", "temperature": 0.3]),
        ("api.cerebras.ai", "qwen-3.8-27b", ["reasoning_effort": "none", "temperature": 0.3]),
        ("openrouter.ai", "anthropic/claude-haiku", ["provider": ["sort": "throughput", "preferred_max_latency": ["p90": 2.5]]]),
        ("api.openai.com", "gpt-4o", [:]),
        ("api.groq.com", "llama-3.3-70b-versatile", [:]),
        ("notes.example", "gpt-5.4-mini", [:]),
        ("localhost", "gpt-oss-120b", [:]),
        (nil, "gpt-5.4", [:]),
    ]
    for item in cases {
        let fields = APINotesModel.lowLatencyFields(host: item.host, model: item.model)
        #expect(NSDictionary(dictionary: fields).isEqual(to: item.fields), "\(item.host ?? "nil") \(item.model)")
    }
}

@Test func onlyLowLatencyRequestsCarryReasoningFields() throws {
    var connection = SpeechConnection(api: .openAICompatible)
    connection.endpoint = "https://api.openai.com/v1/chat/completions"
    connection.modelID = "gpt-5.4-mini"
    let plain = try APINotesModel(connection: connection).requestBody("hello", json: true)
    #expect(Set(plain.keys) == ["model", "stream", "messages", "response_format"])
    let fast = try APINotesModel(connection: connection, instructions: "Edit.", lowLatency: true).requestBody("hello", json: false)
    #expect(Set(fast.keys) == ["model", "stream", "messages", "reasoning_effort", "temperature"])
    #expect(fast["reasoning_effort"] as? String == "none")
    #expect(fast["model"] as? String == "gpt-5.4-mini")
    let messages = try #require(fast["messages"] as? [[String: String]])
    #expect(messages == [["role": "system", "content": "Edit."], ["role": "user", "content": "hello"]])
}

@Test func notesModelsStayOnDefaultReasoningUnlessAskedForLowLatency() throws {
    var settings = AppSettings()
    let connection = SpeechConnection(api: .openAICompatible)
    settings.notesConnections = [connection]
    settings.notesSelection = .connection(connection.id)
    #expect((try MeetingNotesGenerator.languageModel(settings) as? APINotesModel)?.lowLatency == false)
    #expect((try MeetingNotesGenerator.languageModel(settings, lowLatency: true) as? APINotesModel)?.lowLatency == true)
    for cli in NotesCLI.allCases {
        settings.notesSelection = .cli(cli)
        #expect((try MeetingNotesGenerator.languageModel(settings) as? CLINotesModel)?.lowLatency == false)
        #expect((try MeetingNotesGenerator.languageModel(settings, lowLatency: true) as? CLINotesModel)?.lowLatency == true)
    }
}

@Test func lowLatencyCLIsAppendOnlyTheirDocumentedEffortFlag() {
    let claude = CLINotesModel(cli: .claudeCode, model: "")
    let fastClaude = CLINotesModel(cli: .claudeCode, model: "", lowLatency: true)
    #expect(!claude.arguments.contains("--effort"))
    #expect(fastClaude.arguments == claude.arguments + ["--effort", "low"])
    #expect(fastClaude.arguments.contains("--safe-mode"))
    let codex = CLINotesModel(cli: .codex, model: "")
    let fastCodex = CLINotesModel(cli: .codex, model: "", lowLatency: true)
    #expect(!codex.arguments.contains { $0.hasPrefix("model_reasoning_effort") })
    #expect(fastCodex.arguments == codex.arguments + ["-c", "model_reasoning_effort=\"low\""])
    #expect(fastCodex.arguments.contains("read-only"))
}

@Test func warmUpClipIsOneQuietSecondThatWhisperStillTranscribes() throws {
    let url = try WarmUpClip.url()
    #expect(try WarmUpClip.url() == url)
    let file = try AVAudioFile(forReading: url)
    #expect(file.processingFormat.sampleRate == 16_000)
    #expect(file.processingFormat.channelCount == 1)
    #expect(file.length == 16_000)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    #expect(WhisperKitProvider.containsSignal(in: samples))
    #expect(samples.allSatisfy { abs($0) <= 0.001 })
}
