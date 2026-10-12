import Foundation

/// What to learn from one correction the rules found, as decided by the notes model or by the rules alone.
public enum CorrectionDecision: Equatable, Sendable {
    case replacementAndVocabulary(heard: String, corrected: String)
    case replacementOnly(heard: String, corrected: String)
    case vocabularyOnly(String)
    case reject

    /// The vocabulary entry to add; a replacement entry also boosts its spelling, and everyday words are never rewritten.
    public func entry() -> VocabularyEntry? {
        switch self {
        case .replacementAndVocabulary(let heard, let corrected):
            CorrectionLearner.isCommon(heard)
                ? VocabularyEntry(phrase: corrected, replacement: "", learned: true)
                : VocabularyEntry(phrase: heard, replacement: corrected, learned: true)
        case .replacementOnly(let heard, let corrected):
            CorrectionLearner.isCommon(heard) ? nil : VocabularyEntry(phrase: heard, replacement: corrected, learned: true)
        case .vocabularyOnly(let corrected):
            VocabularyEntry(phrase: corrected, replacement: "", learned: true)
        case .reject:
            nil
        }
    }

    /// The entries these decisions add to a vocabulary, skipping terms it already has and stopping at 200 entries.
    public static func entries(for decisions: [CorrectionDecision], in vocabulary: [VocabularyEntry]) -> [VocabularyEntry] {
        var known = Set(vocabulary.flatMap { [$0.phrase.lowercased(), $0.replacement.lowercased()] })
        var added: [VocabularyEntry] = []
        for entry in decisions.compactMap({ $0.entry() }) {
            let terms = Set([entry.phrase, entry.replacement].filter { !$0.isEmpty }.map { $0.lowercased() })
            guard vocabulary.count + added.count < 200, known.isDisjoint(with: terms) else { continue }
            added.append(entry)
            known.formUnion(terms)
        }
        return added
    }
}

/// Asks the notes model which of the rules' corrections are worth learning, adapted from VoiceInk's Auto Learn reviewer.
public enum CorrectionReviewer {
    static let fields: Set<String> = ["candidateID", "learningAction", "incorrectTextToReplace", "correctedVocabularyTerm"]

    static let instructions = """
        Review speech-to-text corrections. Each candidate has originalText and correctedText containing the edit plus up to three surrounding words on each side.

        Mandatory personal-name rule: A personal name is one indivisible term. For a visible multiword personal name, incorrectTextToReplace and correctedVocabularyTerm must contain every visible name component, including every unchanged component. Apply this rule even when only a middle name, surname, particle, spacing, punctuation, or suffix changed. Returning only the changed fragment or one component of a visible multiword name is invalid. When only one personal-name component is visible, such as only a first name or only a surname, it may qualify for addReplacementOnly but must not be added to Vocabulary. Allow a single-word personal name into Vocabulary only when context clearly establishes that the person is genuinely known by that complete mononym, not merely because only one name component appears in the snippet. Never invent name components that are not visible.

        Return exactly one decision for each candidate. If learnable and ordinary edits are mixed in one candidate, return only the learnable correction.

        Before selecting an action, every acceptance must pass both gates:

        1. Phonetic evidence: the changed source and destination spans must recognizably resemble two renderings of the same spoken term. Judge a multiword personal name collectively. Differences caused by accent, transliteration, word boundaries, hyphenation, or omitted diacritics may still be phonetic when the pronunciations plausibly correspond. Related meaning, context, specificity, private status, and Vocabulary usefulness are not themselves phonetic evidence. Reject absent or uncertain resemblance.

        2. No semantic rewrite: reject edits that change meaning or replace coherent language (a description, role, category, purpose, location, relationship, criterion, synonym, or placeholder) with a specific person, place, product, service, or term. Discard them completely even when the destination qualifies for Vocabulary.

        Only edits passing both gates may be accepted. Audit every acceptance against both gates before returning it; convert failures or uncertainty to rejectCorrection with both text fields null.

        Choose one learningAction:

        1. addReplacementAndVocabulary: the corrected term passes the Vocabulary gate and the original plausibly sounds like it.
        2. addReplacementOnly: use for a distinctive, unambiguous, user-specific correction that is worth applying again but whose corrected term should not enter Vocabulary. This includes a learnable correction to a single visible first name or surname when the person's complete name is not visible. Never use this as a fallback for public, common, or generic terms.
        3. addVocabularyOnly: the corrected term passes the Vocabulary gate and the pair passes the phonetic gate, but the source is too broad or ambiguous for a safe global replacement. Never use this for a partial personal name, coherent descriptions, semantic rewrites, deliberate abbreviations, or expansions.
        4. rejectCorrection: nothing is safely reusable, including ordinary wording, grammar, style, meaning, facts, numbers, dates, abbreviations, expansions, changed qualifiers, editions, and generic type words.

        Vocabulary is primarily for complete personal names. A person's first name, surname, or other single component must not enter Vocabulary by itself unless it is clearly the person's complete mononym. This personal-name restriction does not apply to qualifying non-person entities: a single-token internal brand, project, private product, username, specialized term, small organization, or uncommon local place may enter Vocabulary when it is genuinely user-specific, private, or obscure enough to improve recognition.

        Use context to identify user-specific entities. “Call”, “email”, “ask”, “invite”, or “send to” supports interpreting the adjacent text as a personal name. For a phonetically plausible personal name, spelling, apostrophe, spacing, hyphenation, and diacritic corrections are learnable, not formatting-only edits. A personal name remains learnable when it belongs to a well-known or public person. Labels such as “project”, “internal”, “repository”, “account”, “tenant”, or “pipeline” similarly support a user-specific entity. Context never substitutes for phonetic evidence or permits a semantic rewrite.

        Do not learn ordinary words. A brand, product, technology, place, or organization may be learned only when the original is a phonetic mishearing of its name, such as “post hog” to “PostHog” or “super base” to “Supabase”. Outside that and the user-specific contexts above, capitalization or proper-noun appearance alone is insufficient; when uncertain, reject.

        A change in letter case alone is learnable only as addVocabularyOnly, for a term whose casing is distinctive, such as “posthog” to “PostHog”. Reject other case-only changes and partial unsafe mappings.

        For replacement actions, incorrectTextToReplace must be an exact run of whole words from that candidate's originalText that includes every changed word, and correctedVocabularyTerm must be copied the same way from that candidate's correctedText. Each term is at most 100 characters. For addVocabularyOnly set incorrectTextToReplace to null. For rejectCorrection set both fields to null.

        Before returning a personal-name decision, treat a visible multiword name as one indivisible term and verify that both fields contain the complete original and corrected names, even if only one component changed. Example: "Prakash Joshi Pages" to "Prakash Joshi Pax" must use the complete names, never only "Pages" to "Pax". If only one first name or surname is visible and the correction is otherwise safe and learnable, return addReplacementOnly for that visible component. Do not add it to Vocabulary and do not reject it merely because the person's full name is unavailable. Use a Vocabulary action for a single-word personal name only when the context clearly identifies a genuine mononym.

        Return only one JSON array. Do not return an outer object, reviewDecisions key, explanation, Markdown, or code fence. Each array object must contain exactly these four fields: candidateID, learningAction, incorrectTextToReplace, and correctedVocabularyTerm.

        Exact output format:
        [{"candidateID":0,"learningAction":"addReplacementAndVocabulary","incorrectTextToReplace":"original term","correctedVocabularyTerm":"corrected term"},{"candidateID":1,"learningAction":"rejectCorrection","incorrectTextToReplace":null,"correctedVocabularyTerm":null}]

        Allowed actions are addReplacementAndVocabulary, addReplacementOnly, addVocabularyOnly, and rejectCorrection. Copy every integer candidateID exactly and return each input candidateID exactly once.
        """

    private struct Candidate: Encodable {
        let candidateID: Int
        let originalText: String
        let correctedText: String
    }

    private struct Reply: Decodable {
        enum Action: String, Decodable {
            case addReplacementAndVocabulary, addReplacementOnly, addVocabularyOnly, rejectCorrection
        }

        let candidateID: Int
        let learningAction: Action
        let incorrectTextToReplace: String?
        let correctedVocabularyTerm: String?
    }

    /// Whether an edit may go to the notes model: English text, Medium cleanup and a ready notes model, as for polishing.
    public static func mayReview(_ edited: String, settings: AppSettings) -> Bool {
        settings.cleanup == .medium && MeetingNotesGenerator.availability(settings: settings) == .available
            && TranscriptCleaner.isEnglish(edited, language: settings.language == "auto" ? nil : settings.language)
    }

    /// Reviews corrections only when `mayReview` allows it, within 7 seconds; nil means learn by the rules alone.
    public static func review(_ candidates: [LearnedCorrection], from original: String, to edited: String, settings: AppSettings) async -> [CorrectionDecision]? {
        guard !candidates.isEmpty, mayReview(edited, settings: settings),
              let request = request(for: candidates, from: original, to: edited),
              let model = try? MeetingNotesGenerator.languageModel(settings, instructions: instructions, lowLatency: true) else { return nil }
        return await withTaskGroup(of: String?.self) { group in
            group.addTask { try? await model.respond(to: request) }
            group.addTask {
                try? await Task.sleep(for: .seconds(7))
                return nil
            }
            let reply = await group.next() ?? nil
            group.cancelAll()
            return reply.flatMap { parse(reply: $0, candidates: candidates, original: original, edited: edited) }
        }
    }

    /// The numbered excerpts before and after each edit, in the JSON shape the instructions describe.
    static func request(for candidates: [LearnedCorrection], from original: String, to edited: String) -> String? {
        guard let excerpts = excerpts(of: candidates, from: original, to: edited),
              let data = try? JSONEncoder().encode(["candidatesForReview": excerpts.enumerated().map {
                  Candidate(candidateID: $0.offset, originalText: $0.element.original, correctedText: $0.element.edited)
              }]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// One decision per candidate, in candidate order, validated as VoiceInk does; nil when any part of the reply can't be trusted.
    static func parse(reply: String, candidates: [LearnedCorrection], original: String, edited: String) -> [CorrectionDecision]? {
        guard let excerpts = excerpts(of: candidates, from: original, to: edited) else { return nil }
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), text.hasSuffix("```"), let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...].dropLast(3))
        }
        let data = Data(text.utf8)
        guard let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], objects.allSatisfy({ Set($0.keys) == fields }),
              let replies = try? JSONDecoder().decode([Reply].self, from: data), replies.count == candidates.count else { return nil }
        var decisions = [CorrectionDecision?](repeating: nil, count: candidates.count)
        for reply in replies {
            let id = reply.candidateID
            guard decisions.indices.contains(id), decisions[id] == nil,
                  let decision = decision(reply, for: candidates[id], in: excerpts[id]) else { return nil }
            decisions[id] = decision
        }
        return decisions.compactMap { $0 }
    }

    private static func decision(_ reply: Reply, for candidate: LearnedCorrection, in excerpt: (original: String, edited: String)) -> CorrectionDecision? {
        if reply.learningAction == .rejectCorrection {
            return reply.incorrectTextToReplace == nil && reply.correctedVocabularyTerm == nil ? .reject : nil
        }
        guard let corrected = term(reply.correctedVocabularyTerm, covering: candidate.corrected, in: excerpt.edited) else { return nil }
        if CorrectionLearner.isCommon(corrected) { return .reject }
        if reply.learningAction == .addVocabularyOnly {
            return reply.incorrectTextToReplace == nil ? .vocabularyOnly(corrected) : nil
        }
        guard let heard = term(reply.incorrectTextToReplace, covering: candidate.heard, in: excerpt.original),
              heard != corrected, !heard.contains(",") else { return nil }
        if heard.caseInsensitiveCompare(corrected) == .orderedSame { return .vocabularyOnly(corrected) }
        return reply.learningAction == .addReplacementOnly
            ? .replacementOnly(heard: heard, corrected: corrected)
            : .replacementAndVocabulary(heard: heard, corrected: corrected)
    }

    /// The model's term when it is whole words of the excerpt that include the rules' own term, so review only narrows what the rules found.
    private static func term(_ text: String?, covering found: String, in excerpt: String) -> String? {
        guard let term = text?.trimmingCharacters(in: .whitespacesAndNewlines), (1...100).contains(term.count),
              wordRange(of: term, in: excerpt) != nil, wordRange(of: found, in: term) != nil else { return nil }
        return term
    }

    private static func wordRange(of term: String, in text: String) -> Range<String.Index>? {
        text.range(of: "(?<![\\p{L}\\p{M}\\p{N}_])\(NSRegularExpression.escapedPattern(for: term))(?![\\p{L}\\p{M}\\p{N}_])", options: .regularExpression)
    }

    private static func excerpts(of candidates: [LearnedCorrection], from original: String, to edited: String) -> [(original: String, edited: String)]? {
        let excerpts = candidates.compactMap { candidate in
            excerpt(around: candidate.heard, in: original).flatMap { heard in excerpt(around: candidate.corrected, in: edited).map { (original: heard, edited: $0) } }
        }
        return excerpts.count == candidates.count ? excerpts : nil
    }

    /// The first whole-word match of the term with up to three words on each side, so the model sees the edit without the rest of the field.
    static func excerpt(around term: String, in text: String) -> String? {
        guard let range = wordRange(of: term, in: text) else { return nil }
        let before = text[..<range.lowerBound].split(whereSeparator: \.isWhitespace).suffix(3)
        let after = text[range.upperBound...].split(whereSeparator: \.isWhitespace).prefix(3)
        return String(text[(before.first?.startIndex ?? range.lowerBound)..<(after.last?.endIndex ?? range.upperBound)])
    }
}
