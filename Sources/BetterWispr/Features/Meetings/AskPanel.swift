import BetterWisprCore
import SwiftUI

struct AskExchange: Identifiable {
    enum Reply {
        case waiting, answer(MeetingAnswer), failure(String)
    }

    let id = UUID()
    let question: String
    var reply = Reply.waiting

    var isWaiting: Bool {
        if case .waiting = reply { true } else { false }
    }
}

struct AskPanel: View {
    let model: AppModel
    let placeholder: String
    @Binding var exchanges: [AskExchange]
    let showsMeetingTitles: Bool
    let onCite: (MeetingLine) -> Void
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField(placeholder, text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(ask)
                        .disabled(unavailable != nil)
                        .accessibilityLabel(placeholder)
                    Button("Ask", action: ask)
                        .disabled(!canAsk)
                    if !exchanges.isEmpty, !isWaiting {
                        Button("Clear") { exchanges.removeAll() }
                            .help("Clear these questions and answers")
                    }
                }
                if let unavailable {
                    Text(unavailable).font(.callout).foregroundStyle(.secondary)
                }
            }
            ForEach(exchanges.reversed()) { exchange in
                row(exchange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settings: AppSettings { model.meetings.notesSettings.askSettings }

    private var unavailable: String? {
        if case .unavailable(let reason) = MeetingNotesGenerator.availability(settings: settings) { reason } else { nil }
    }

    private var isWaiting: Bool { exchanges.contains(where: \.isWaiting) }

    private var question: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canAsk: Bool { unavailable == nil && !isWaiting && !question.isEmpty }

    private func ask() {
        guard canAsk else { return }
        exchanges.append(AskExchange(question: question))
        draft = ""
    }

    private func row(_ exchange: AskExchange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exchange.question)
                .font(.system(size: 15, weight: .semibold))
                .textSelection(.enabled)
            switch exchange.reply {
            case .waiting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Asking \(settings.notesModelName)…").foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Cancel") { exchanges.removeAll { $0.id == exchange.id } }
                }
            case .failure(let message):
                Text(message).foregroundStyle(.secondary).textSelection(.enabled)
            case .answer(let answer):
                Text((try? AttributedString(markdown: answer.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    ?? AttributedString(answer.text))
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                if !answer.citations.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(answer.citations, id: \.self, content: citation)
                    }
                }
                Text("Answered with \(answer.modelName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func citation(_ citation: MeetingAnswer.Citation) -> some View {
        let line = citation.line
        let title = showsMeetingTitles ? model.meetings.meeting(line.meetingID)?.displayTitle : nil
        return Button { onCite(line) } label: {
            HStack(spacing: 6) {
                Text("[\(citation.number)] \(line.label)").fontWeight(.medium).monospacedDigit().layoutPriority(1)
                if let title { Text(title) }
                Text(line.text).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(line.text)
        .accessibilityLabel(["Line \(citation.number)", line.label, title].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(line.text)
    }
}

extension View {
    /// Asks the newest waiting exchange about `meetings` with the Ask model, and cancels it when the exchange or the view goes away.
    func answering(_ exchanges: Binding<[AskExchange]>, model: AppModel, meetings: @escaping @MainActor () -> [Meeting]) -> some View {
        task(id: exchanges.wrappedValue.last?.id) {
            guard let exchange = exchanges.wrappedValue.last, exchange.isWaiting else { return }
            let about = meetings()
            let settings = model.meetings.notesSettings.askSettings
            let reply: AskExchange.Reply
            do {
                reply = .answer(try await MeetingQuestion.ask(exchange.question, about: about, settings: settings))
            } catch {
                guard !Task.isCancelled else { return }
                reply = .failure(error.localizedDescription)
            }
            guard let index = exchanges.wrappedValue.firstIndex(where: { $0.id == exchange.id }) else { return }
            exchanges.wrappedValue[index].reply = reply
        }
    }
}
