import Combine
import Foundation

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var generatedInsight: Insight?
    @Published private(set) var isGenerating = false
    @Published private(set) var generationError: String?
    @Published private(set) var fromDate: Date
    @Published private(set) var toDate: Date

    private let noteStore: any NoteStore
    private let healthModel: any HealthLanguageModel
    private let calendar: Calendar
    private let maximumToDate: Date

    init(
        noteStore: any NoteStore,
        healthModel: any HealthLanguageModel,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) {
        self.noteStore = noteStore
        self.healthModel = healthModel
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
        defer { isGenerating = false }

        do {
            let patientID = try await noteStore.patientProfiles().first?.id
            let entries = try await noteStore.diaryEntries(patientID: patientID)
            let endExclusive = calendar.date(
                byAdding: .day,
                value: 1,
                to: toDate
            ) ?? toDate
            let selectedEntries = entries.filter {
                $0.day >= fromDate && $0.day < endExclusive
            }
            let text = try await healthModel.generateInsights(
                from: selectedEntries
            )
            let insight = Insight(
                day: Date(),
                generatedFrom: fromDate,
                generatedTo: toDate,
                promptText: "Generate an insight from the selected diary period.",
                text: text
            )
            try await noteStore.saveInsight(insight)
            generatedInsight = insight
        } catch {
            generationError = "Your insight could not be generated."
        }
    }
}
