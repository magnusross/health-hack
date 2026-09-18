import Foundation
import SwiftData

/// Keeps the summary prompt in the PROMPT table, as `rules.txt` describes.
///
/// Generation reads the template from `SummaryPromptTemplate.dailySummary`,
/// which stays the source of truth; this only makes sure the schema reflects
/// the prompt the app is actually using.
enum PromptSeeder {
    @MainActor
    static func seedSummaryPrompt(in modelContext: ModelContext) throws {
        let template = SummaryPromptTemplate.dailySummary.text
        let existing = try modelContext.fetch(FetchDescriptor<PromptRecord>())
        guard !existing.contains(where: { $0.text == template }) else { return }

        modelContext.insert(PromptRecord(prompt: Prompt(text: template)))
        try modelContext.save()
    }
}
