import Foundation

/// Writing settings that take over for chosen apps, websites or a spoken trigger word; nil fields inherit.
public struct WritingMode: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    /// Bundle identifiers.
    public var apps: [String]
    /// Hosts with an optional path, as typed, such as "github.com" or "mail.google.com/mail".
    public var websites: [String]
    public var triggerWords: [String]
    public var cleanup: CleanupLevel?
    public var tone: StyleTone?
    public var useScreenContext: Bool?
    /// Extra polish instructions, used only when the effective cleanup is Medium.
    public var instructions: String

    public static let instructionLimit = 2_000

    public init(
        id: UUID = UUID(), name: String = "", isEnabled: Bool = true, apps: [String] = [], websites: [String] = [],
        triggerWords: [String] = [], cleanup: CleanupLevel? = nil, tone: StyleTone? = nil, useScreenContext: Bool? = nil,
        instructions: String = ""
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.apps = apps
        self.websites = websites
        self.triggerWords = triggerWords
        self.cleanup = cleanup
        self.tone = tone
        self.useScreenContext = useScreenContext
        self.instructions = instructions
    }

    /// Unknown levels and tones from a newer version decode as nil, so the mode inherits instead of failing to load.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        apps = try container.decodeIfPresent([String].self, forKey: .apps) ?? []
        websites = try container.decodeIfPresent([String].self, forKey: .websites) ?? []
        triggerWords = try container.decodeIfPresent([String].self, forKey: .triggerWords) ?? []
        cleanup = try container.decodeIfPresent(CleanupLevel.self, forKey: .cleanup)
        tone = try container.decodeIfPresent(StyleTone.self, forKey: .tone)
        useScreenContext = try container.decodeIfPresent(Bool.self, forKey: .useScreenContext)
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
    }

    /// Matches when the URL's host is the pattern's host or a subdomain of it, and its path starts with the pattern's path segments.
    public static func website(_ pattern: String, matches url: String) -> Bool {
        let pattern = address(pattern), url = address(url)
        guard !pattern.host.isEmpty, url.host == pattern.host || url.host.hasSuffix("." + pattern.host) else { return false }
        return pattern.path.isEmpty || url.path == pattern.path || url.path.hasPrefix(pattern.path + "/")
    }

    private static func address(_ text: String) -> (host: String, path: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacing(#/^[a-z][a-z0-9+.\-]*:\/\//#, with: "")
            .replacing(#/^(?:www|\*)\./#, with: "")
        let location = text.prefix { $0 != "?" && $0 != "#" }
        let host = location.prefix { $0 != "/" }
        let path = location.dropFirst(host.count).trimmingCharacters(in: CharacterSet(charactersIn: "/*"))
        return (String(host.prefix { $0 != ":" }), path)
    }

    /// VoiceInk's trigger detection: the longest word first, then mode order, then word order; strips the word from either end.
    static func trigger(in transcript: String, modes: [WritingMode]) -> ModeMatch? {
        let candidates = modes.flatMap { mode in
            mode.triggerWords.map { (mode: mode, word: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        .filter { !$0.word.isEmpty }
        .enumerated()
        .sorted { $0.element.word.count != $1.element.word.count ? $0.element.word.count > $1.element.word.count : $0.offset < $1.offset }
        for (_, candidate) in candidates {
            if let rest = stripping(candidate.word, from: transcript) { return ModeMatch(mode: candidate.mode, transcript: rest) }
        }
        return nil
    }

    static func stripping(_ word: String, from text: String) -> String? {
        if let rest = strippingTrailing(word, from: text) { return strippingLeading(word, from: rest) ?? rest }
        if let rest = strippingLeading(word, from: text) { return strippingTrailing(word, from: rest) ?? rest }
        return nil
    }

    private static func strippingLeading(_ word: String, from text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = text.range(of: word, options: [.caseInsensitive, .anchored]) else { return nil }
        if let next = text[range.upperBound...].first, next.isLetter || next.isNumber { return nil }
        let rest = String(text[range.upperBound...]).replacing(#/^[,.!?;:\s]+/#, with: "")
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }

    /// Unlike VoiceInk, keeps the sentence's closing period, question mark or exclamation mark.
    private static func strippingTrailing(_ word: String, from text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = text.replacing(#/[,.!?;:]+$/#, with: "")
        guard let range = body.range(of: word, options: [.caseInsensitive, .anchored, .backwards]) else { return nil }
        if let previous = body[..<range.lowerBound].last, previous.isLetter || previous.isNumber { return nil }
        var rest = String(body[..<range.lowerBound]).replacing(#/[,;:\s]+$/#, with: "")
        if let end = text.last, ".!?".contains(end), let last = rest.last, !".!?".contains(last) { rest.append(end) }
        return rest
    }
}

/// A resolved mode; `transcript` is the dictation without its trigger word when a trigger word chose the mode.
public struct ModeMatch: Equatable, Sendable {
    public var mode: WritingMode
    public var transcript: String?

    public init(mode: WritingMode, transcript: String? = nil) {
        self.mode = mode
        self.transcript = transcript
    }
}

extension [WritingMode] {
    /// The first enabled mode by tier: a spoken trigger word, then the website, then the app.
    public func match(transcript: String? = nil, url: String? = nil, app: String? = nil) -> ModeMatch? {
        let enabled = filter(\.isEnabled)
        let tiers: [() -> ModeMatch?] = [
            { transcript.flatMap { WritingMode.trigger(in: $0, modes: enabled) } },
            { url.flatMap { url in enabled.first { $0.websites.contains { WritingMode.website($0, matches: url) } } }.map { ModeMatch(mode: $0) } },
            { app.flatMap { app in enabled.first { $0.apps.contains(app) } }.map { ModeMatch(mode: $0) } },
        ]
        return tiers.lazy.compactMap { $0() }.first
    }

    /// Whether any enabled mode lists a website, which is the only reason to read a browser's URL.
    public var needsWebsite: Bool { contains { $0.isEnabled && $0.websites.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } } }
}

extension AppSettings {
    /// These settings with the mode's non-nil overrides; a tone replaces the tone of every app category.
    public func applying(_ mode: WritingMode?) -> AppSettings {
        guard let mode else { return self }
        var settings = self
        settings.cleanup = mode.cleanup ?? cleanup
        settings.useScreenContext = mode.useScreenContext ?? useScreenContext
        if let tone = mode.tone { settings.styles = Dictionary(uniqueKeysWithValues: StyleContext.allCases.map { ($0, tone) }) }
        return settings
    }

    /// Whether Medium cleanup sends the context captured under the starting mode, which needs Medium and screen context too; a trigger word's mode can turn it off but not on.
    public func sharesContext(startedIn mode: WritingMode?, trigger: WritingMode?) -> Bool {
        applying(mode).cleanup == .medium && applying(trigger ?? mode).cleanup == .medium && applying(mode).useScreenContext && trigger?.useScreenContext != false
    }
}
