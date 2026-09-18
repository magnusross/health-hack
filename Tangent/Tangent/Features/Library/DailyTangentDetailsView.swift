import SwiftUI

struct DailyTangentDetailsView: View {
    @StateObject private var model: DailyTangentDetailsViewModel
    private let calendar: Calendar
    private let redoToday: (() -> Void)?
    private let openSettings: (() -> Void)?

    init(
        noteStore: any NoteStore,
        transcriber: (any Transcriber)? = nil,
        summaryGenerator: (any SummaryGenerator)? = nil,
        diaryID: UUID,
        streamsTranscript: Bool = false,
        calendar: Calendar = .autoupdatingCurrent,
        redoToday: (() -> Void)? = nil,
        openSettings: (() -> Void)? = nil
    ) {
        _model = StateObject(
            wrappedValue: DailyTangentDetailsViewModel(
                noteStore: noteStore,
                transcriber: transcriber,
                summaryGenerator: summaryGenerator,
                diaryID: diaryID,
                streamsTranscript: streamsTranscript
            )
        )
        self.calendar = calendar
        self.redoToday = redoToday
        self.openSettings = openSettings
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

                        summarySection(for: entry)

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

    @ViewBuilder
    private func summarySection(for entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Summary")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Color.tangentInk)

            switch model.summaryState {
            case .generating:
                VStack(alignment: .leading, spacing: 12) {
                    if !model.streamingShortSummary.isEmpty {
                        summaryText(model.streamingShortSummary)
                    }
                    HStack(spacing: 9) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Writing your summary…")
                            .font(.system(.footnote, design: .serif))
                            .foregroundStyle(Color.tangentInk.opacity(0.5))
                    }
                }
                .animation(.easeOut(duration: 0.15), value: model.streamingShortSummary)

            case .failed(let message, let needsModel):
                VStack(alignment: .leading, spacing: 12) {
                    Text(message)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Color.tangentInk.opacity(0.6))

                    if needsModel, let openSettings {
                        Button("Choose a model", action: openSettings)
                            .font(.system(.subheadline, design: .serif, weight: .medium))
                            .foregroundStyle(Color.tangentPurple)
                    } else {
                        Button("Try again") {
                            Task { await model.regenerate() }
                        }
                        .font(.system(.subheadline, design: .serif, weight: .medium))
                        .foregroundStyle(Color.tangentPurple)
                    }
                }

            case .idle:
                if model.hasSummary {
                    // Only the short summary belongs on the day's screen. The
                    // long one is stored for insights to read across days.
                    summaryText(entry.summaryShort)
                } else {
                    Text("No summary has been written for this Tangent yet.")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Color.tangentInk.opacity(0.6))
                }
            }
        }
    }

    @ViewBuilder
    private func summaryText(_ text: String) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(Color.tangentInk.opacity(0.9))
                .lineSpacing(6)
                .textSelection(.enabled)
        }
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
