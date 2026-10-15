import Foundation

/// A provider's OpenAI-compatible chat completions URL and a fast model, to fill in a new notes connection.
public struct NotesAPIPreset: Identifiable, Sendable {
    public var name: String
    public var endpoint: String
    public var modelID: String

    public var id: String { name }

    public static let all = [
        NotesAPIPreset(name: "OpenAI", endpoint: "https://api.openai.com/v1/chat/completions", modelID: "gpt-6-luna"),
        NotesAPIPreset(name: "Anthropic", endpoint: "https://api.anthropic.com/v1/chat/completions", modelID: "claude-haiku-5-5"),
        NotesAPIPreset(name: "Google Gemini", endpoint: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
                       modelID: "gemini-3.8-flash"),
        NotesAPIPreset(name: "OpenRouter", endpoint: "https://openrouter.ai/api/v1/chat/completions", modelID: "openai/gpt-6-luna"),
    ]
}
