import Combine
import Foundation

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var generatedInsight: Insight?
    @Published private(set) var isGenerating = false
    /// The insights as the model writes them, until the saved one takes over.
    @Published private(set) var streamingInsight = ""
    @Published private(set) var generationError: String?
    @Published private(set) var fromDate: Date
    @Published private(set) var toDate: Date

    private let noteStore: any NoteStore
    private let languageModel: any DiaryLanguageModel
    private let calendar: Calendar
    private let maximumToDate: Date

    init(
        noteStore: any NoteStore,
        languageModel: any DiaryLanguageModel,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) {
        self.noteStore = noteStore
        self.languageModel = languageModel
        self.calendar = calendar
        let today = calendar.startOfDay(for: now)
        maximumToDate = today
        toDate = today
        fromDate = calendar.date(byAdding: .day, value: -14, to: today) ?? today
    }

    var earliestFromDate: Date {
        calendar.date(byAdding: .day, value: -14, to: toDate) ?? toDate
    }

    var latestToDate: Date {
        maximumToDate
    }

    func setFromDate(_ date: Date) {
        fromDate = min(max(calendar.startOfDay(for: date), earliestFromDate), toDate)
    }

    func setToDate(_ date: Date) {
        toDate = min(calendar.startOfDay(for: date), latestToDate)
        fromDate = min(max(fromDate, earliestFromDate), toDate)
    }

    func generateInsight() async {
        guard !isGenerating else { return }
        isGenerating = true
        generatedInsight = nil
        generationError = nil
        streamingInsight = ""
        defer { isGenerating = false }

        do {
            let profile = try await noteStore.userProfiles().first
            let entries = try await noteStore.diaryEntries(profileID: profile?.id)
            let endExclusive = calendar.date(
                byAdding: .day,
                value: 1,
                to: toDate
            ) ?? toDate
            let selectedEntries = entries.filter {
                $0.day >= fromDate && $0.day < endExclusive
            }
            let summaries = selectedEntries.compactMap(DiarySummary.init)
            guard !summaries.isEmpty else {
                throw DiaryLanguageModelError.notEnoughEntries
            }
            let generated = try await languageModel.generateInsights(
                from: summaries,
                focus: profile?.focus ?? DiaryFocus(),
                period: periodDescription,
                onPartial: { [weak self] partial in
                    Task { @MainActor in
                        guard let self, self.isGenerating else { return }
                        self.streamingInsight = partial
                    }
                }
            )
            let insight = Insight(
                day: Date(),
                generatedFrom: fromDate,
                generatedTo: toDate,
                promptText: generated.promptText,
                text: generated.text
            )
            try await noteStore.saveInsight(insight)
            generatedInsight = insight
            streamingInsight = ""
        } catch {
            // The model says why — no model downloaded, nothing in range —
            // and that is more use than a blanket apology.
            generationError = error.localizedDescription
        }
    }

    /// Names the range back to the reader, e.g. "7 to 13 September".
    private var periodDescription: String {
        let from = fromDate.formatted(.dateTime.day().month(.wide))
        let to = toDate.formatted(.dateTime.day().month(.wide))
        return from == to ? from : "\(from) to \(to)"
    }
}
