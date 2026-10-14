import Foundation

/// Text around the dictation target that Parakeet may spell names from and Medium cleanup may show the notes model, each part trimmed and capped.
public struct DictationContext: Equatable, Sendable {
    public private(set) var selectedText: String?
    public private(set) var clipboard: String?
    public private(set) var window: String?

    public init(selectedText: String? = nil, clipboard: String? = nil, window: String? = nil) {
        self.selectedText = Self.capped(selectedText, at: 2_000)
        self.clipboard = Self.capped(clipboard, at: 2_000)
        self.window = Self.capped(window, at: 4_000)
    }

    var characters: Int { [selectedText, clipboard, window].reduce(0) { $0 + ($1?.count ?? 0) } }

    /// Up to `limit` mixed-case words such as WhisperKit, and capitalized words such as Supabase or Mem0 that `isKnownWord` rejects, from the selection and window, most frequent first.
    func spellingTerms(limit: Int = 20, isKnownWord: (String) -> Bool) -> [String] {
        let text = [selectedText, window].compactMap { $0 }.joined(separator: "\n")
        let tokens: [Substring] = text.split { !$0.isLetter && !$0.isNumber }
        let words = tokens.filter { $0.count > 2 && $0.contains(where: \.isUppercase) }.map(String.init)
        let counts = Dictionary(words.map { ($0, 1) }, uniquingKeysWith: +)
        var seen = Set<String>()
        let ranked = words.filter { seen.insert($0).inserted }.sorted { counts[$0, default: 0] > counts[$1, default: 0] }
        var terms: [String] = []
        for word in ranked where terms.count < limit && (Self.isMixedCase(word) || !isKnownWord(word)) { terms.append(word) }
        return terms
    }

    private static func isMixedCase(_ word: String) -> Bool {
        word.dropFirst().contains(where: \.isUppercase) && word.contains(where: \.isLowercase)
    }

    /// Drops the window text, then the clipboard, then the selection until at most `limit` characters remain.
    func fitting(_ limit: Int) -> DictationContext {
        var context = self
        for part in [\DictationContext.window, \.clipboard, \.selectedText] where context.characters > limit {
            context[keyPath: part] = nil
        }
        return context
    }

    /// Trims `text` and cuts it to at most `limit` characters at a word boundary; empty text becomes nil.
    static func capped(_ text: String?, at limit: Int) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        guard text.count > limit else { return text }
        let cut = text.index(text.startIndex, offsetBy: limit)
        let end = text[cut].isWhitespace ? cut : text[..<cut].lastIndex(where: \.isWhitespace) ?? cut
        return String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Task where Failure == Never {
    /// Waits for the value until `limit` passes, then returns nil, cancelling the task unless `cancellingOnTimeout` is false.
    public func value(within limit: Duration, cancellingOnTimeout: Bool = true) async -> Success? {
        let (results, continuation) = AsyncStream.makeStream(of: Success?.self)
        Task<Void, Never> { continuation.yield(await value) }
        let timer = Task<Void, Never> {
            try? await Task<Never, Never>.sleep(for: limit)
            continuation.yield(nil)
        }
        var iterator = results.makeAsyncIterator()
        let result = await iterator.next() ?? nil
        timer.cancel()
        if result == nil, cancellingOnTimeout { cancel() }
        return result
    }
}
