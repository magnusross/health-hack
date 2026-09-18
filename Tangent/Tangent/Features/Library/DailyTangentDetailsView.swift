import SwiftUI

struct DailyTangentDetailsView: View {
    @StateObject private var model: DailyTangentDetailsViewModel
    private let calendar: Calendar
    private let redoToday: (() -> Void)?

    init(
        noteStore: any NoteStore,
        transcriber: (any Transcriber)? = nil,
        healthModel: (any HealthLanguageModel)? = nil,
        diaryID: UUID,
        streamsTranscript: Bool = false,
        calendar: Calendar = .autoupdatingCurrent,
        redoToday: (() -> Void)? = nil
    ) {
        _model = StateObject(
            wrappedValue: DailyTangentDetailsViewModel(
                noteStore: noteStore,
                transcriber: transcriber,
                healthModel: healthModel,
                diaryID: diaryID,
                streamsTranscript: streamsTranscript
            )
        )
        self.calendar = calendar
        self.redoToday = redoToday
    }

    var body: some View {
        Group {
            if let entry = model.entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(
                            entry.day,
                            format: .dateTime
                                .weekday(.wide)
                                .day()
                                .month(.wide)
                                .year()
                        )
                        .font(.system(.title2, design: .serif, weight: .medium))
                        .foregroundStyle(Color.tangentInk)

                        detailSection(
                            title: "Summary",
                            text: summaryText(for: entry)
                        )

                        Divider()
                            .overlay(Color.tangentInk.opacity(0.1))

                        detailSection(
                            title: "Transcript",
                            text: transcriptText
                        )

                        if calendar.isDateInToday(entry.day), let redoToday {
                            Button("Redo today’s Tangent", action: redoToday)
                                .font(.system(.body, design: .serif, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.tangentPurple)
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                                .padding(.top, 8)
                                .accessibilityHint("Opens a new recording for today")
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let loadError = model.loadError {
                Text(loadError)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color.tangentInk.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.tangentWash)
        .navigationTitle("Daily Tangent")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.start()
        }
    }

    private var transcriptText: String {
        if let transcript = model.transcript, !transcript.isEmpty {
            return transcript
        }
        if model.isTranscribing {
            return "Transcribing…"
        }
        if let loadError = model.loadError {
            return loadError
        }
        return "No transcript is available for this entry."
    }

    private func summaryText(for entry: DiaryEntry) -> String {
        if !entry.summaryShort.isEmpty {
            return entry.summaryShort
        }
        return entry.summaryLong
    }

    private func detailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Color.tangentInk)

            Text(text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(Color.tangentInk.opacity(0.82))
                .lineSpacing(6)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    let container = try! TangentModelContainer.make(inMemory: true)
    let store = SwiftDataNoteStore(modelContext: container.mainContext)
    NavigationStack {
        DailyTangentDetailsView(noteStore: store, diaryID: UUID())
    }
}
