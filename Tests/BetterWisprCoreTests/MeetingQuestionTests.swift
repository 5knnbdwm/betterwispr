import Foundation
import Testing
@testable import BetterWisprCore

@Test func meetingQuestionNumbersTranscriptThenThoughtsAndMapsCitationsToLines() async throws {
    var meeting = Meeting(title: "Deck review", notes: "Check the discount\n\n  Ask Debra about Q3  ", modelName: "Parakeet", language: "en")
    meeting.participantNames = [1: "Debra"]
    let mine = MeetingSegment(speaker: .me, start: 5, duration: 2, text: "Can you send the deck?", rawText: "")
    let hers = MeetingSegment(speaker: .them, start: 12, duration: 3, text: " I'll send it Friday. ", rawText: "", participant: 1)
    meeting.insert(mine)
    meeting.insert(hers)
    let model = FakeAskModel(reply: "  Debra sends it Friday [2]. You noted a discount [3].\n")

    let answer = try await MeetingQuestion.ask("  When does the deck arrive?  ", about: [meeting], model: model, modelName: "Fake model")

    let prompt = try #require(await model.prompts.first)
    #expect(prompt == """
        Meeting "Deck review", \(meeting.createdAt.formatted(date: .abbreviated, time: .shortened)):
        [1] 00:05 Me: Can you send the deck?
        [2] 00:12 Debra: I'll send it Friday.
        [3] My thoughts: Check the discount
        [4] My thoughts: Ask Debra about Q3

        Question: When does the deck arrive?
        """)
    #expect(answer.text == "Debra sends it Friday [2]. You noted a discount [3].")
    #expect(answer.citations.map(\.number) == [2, 3])
    #expect(answer.citations[0].line.segmentID == hers.id)
    #expect(answer.citations[0].line.meetingID == meeting.id)
    #expect(answer.citations[0].line.label == "00:12 Debra")
    #expect(answer.citations[1].line.segmentID == nil)
    #expect(answer.citations[1].line.meetingID == meeting.id)
    #expect(answer.modelName == "Fake model")
}

@Test func meetingQuestionKeepsOnlyCitationsThatNameSourceLines() {
    let id = UUID()
    let sources = (1...3).map { MeetingLine(meetingID: id, segmentID: UUID(), label: "00:0\($0) Me", text: "Line \($0)") }

    let answer = MeetingQuestion.answer("Debra sends it [2]. Pricing [2, 3] and [0] and [9] and [abc] and [3-5].", sources: sources, modelName: "Fake")
    #expect(answer.text == "Debra sends it [2]. Pricing [2, 3] and and and [abc] and [3-5].")
    #expect(answer.citations.map(\.number) == [2, 3])
    #expect(answer.citations.map(\.line) == [sources[1], sources[2]])

    let trimmed = MeetingQuestion.answer("Both [3, 7] and [ 1 ].", sources: sources, modelName: "Fake")
    #expect(trimmed.text == "Both [3] and [ 1 ].")
    #expect(trimmed.citations.map(\.number) == [3, 1])
}

@Test func meetingQuestionNumbersAcrossMeetingsInOrder() async throws {
    var first = Meeting(title: "Kickoff", createdAt: Date(timeIntervalSince1970: 1_000), modelName: "Parakeet", language: "en")
    first.insert(MeetingSegment(speaker: .me, start: 1, duration: 2, text: "Welcome everyone.", rawText: ""))
    first.insert(MeetingSegment(speaker: .them, start: 4, duration: 2, text: "Glad to be here.", rawText: ""))
    var second = Meeting(title: "Follow-up", createdAt: Date(timeIntervalSince1970: 90_000), notes: "Budget is fixed", modelName: "Parakeet", language: "en")
    let answerLine = MeetingSegment(speaker: .them, start: 30, duration: 2, text: "We ship in June.", rawText: "")
    second.insert(answerLine)
    let model = FakeAskModel(reply: "It ships in June [3].")

    let answer = try await MeetingQuestion.ask("When do we ship?", about: [first, second], model: model, modelName: "Fake")

    let prompt = try #require(await model.prompts.first)
    let firstHeader = "Meeting \"Kickoff\", \(first.createdAt.formatted(date: .abbreviated, time: .shortened)):"
    let secondHeader = "Meeting \"Follow-up\", \(second.createdAt.formatted(date: .abbreviated, time: .shortened)):"
    #expect(prompt.contains("\(firstHeader)\n[1] 00:01 Me: Welcome everyone.\n[2] 00:04 Them: Glad to be here.\n\n\(secondHeader)\n[3] 00:30 Them: We ship in June.\n[4] My thoughts: Budget is fixed\n"))
    #expect(answer.citations.count == 1)
    #expect(answer.citations.first?.line.meetingID == second.id)
    #expect(answer.citations.first?.line.segmentID == answerLine.id)
}

@Test func meetingQuestionFitsTheBudgetAroundTheRarestQuestionWord() throws {
    var meeting = Meeting(title: "Long call", modelName: "Parakeet", language: "en")
    for index in 0..<41 {
        let text = index == 20 ? "The pricing goes up in May." : "Weather and small talk, round \(index)."
        meeting.insert(MeetingSegment(speaker: .them, start: TimeInterval(index * 10), duration: 5, text: text, rawText: ""))
    }
    let all = MeetingQuestion.lines(of: meeting)
    let budget = 320

    let selected = MeetingQuestion.sources(for: "What changed about pricing?", in: [meeting], budget: budget)

    let header = "Meeting \"Long call\", \(meeting.createdAt.formatted(date: .abbreviated, time: .shortened)):"
    let cost = selected.reduce(header.count + 2) { $0 + $1.label.count + $1.text.count + 10 }
    #expect(cost <= budget)
    #expect(selected.count < 10)
    #expect(Array(all[19...21]).allSatisfy(selected.contains))
    #expect(selected == all.filter(selected.contains))
    #expect(MeetingQuestion.sources(for: "What changed about pricing?", in: [meeting], budget: 100_000) == all)
}

@Test func askSelectionDecodesLegacyRoundTripsAndResetsWithItsConnection() throws {
    let legacy = #"{"autoPaste":true,"language":"auto","launchAtLogin":false,"saveHistory":true,"selectedModelID":"apple","showCapsule":true,"silenceThreshold":0.002,"notesModel":"llama3.1:8b"}"#
    var settings = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
    #expect(settings.askSelection == nil)
    #expect(settings.askSettings.notesSelection == settings.notesSelection)

    settings.askSelection = .ollama("llama3")
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded == settings)
    #expect(decoded.askSettings.notesModelName == "Ollama · llama3")
    #expect(decoded.notesSelection == .ollama("llama3.1:8b"))

    let unknown = legacy.dropLast() + #","askSelection":{"telepathy":{}}}"#
    let fallback = try JSONDecoder().decode(AppSettings.self, from: Data(unknown.utf8))
    #expect(fallback.askSelection == nil)
    #expect(fallback.notesSelection == .ollama("llama3.1:8b"))

    let removed = UUID()
    let kept = UUID()
    settings.notesSelection = .connection(removed)
    settings.askSelection = .connection(removed)
    settings.deselectNotesConnection(removed)
    #expect(settings.notesSelection == .apple)
    #expect(settings.askSelection == nil)
    settings.notesSelection = .connection(removed)
    settings.askSelection = .connection(kept)
    settings.deselectNotesConnection(removed)
    #expect(settings.notesSelection == .apple)
    #expect(settings.askSelection == .connection(kept))
}

@Test func meetingQuestionWithNothingToReadThrowsWithoutCallingTheModel() async {
    let model = FakeAskModel(reply: "Anything [1]")
    let blank = Meeting(notes: " \n\t\n", segments: [MeetingSegment(speaker: .me, start: 0, duration: 1, text: "   ", rawText: "")],
                        modelName: "Parakeet", language: "en")
    for meetings in [[], [blank]] {
        await #expect(throws: MeetingNotesError.self) {
            try await MeetingQuestion.ask("What happened?", about: meetings, model: model, modelName: "Fake")
        }
    }
    #expect(await model.prompts.isEmpty)
}

private actor FakeAskModel: NotesLanguageModel {
    let reply: String
    private(set) var prompts: [String] = []

    init(reply: String) { self.reply = reply }

    func respond(to prompt: String) -> String {
        prompts.append(prompt)
        return reply
    }

    func draft(_ prompt: String) -> NotesDraft {
        Issue.record("Ask must not request structured notes")
        return NotesDraft(title: "", overview: "", keyPoints: [], decisions: [], actionItems: [])
    }
}
