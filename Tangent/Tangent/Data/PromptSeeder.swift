import Foundation
import SwiftData

/// Keeps the app's prompts in the PROMPT table, as `rules.txt` describes.
///
/// Generation reads its template from `PromptTemplate`, which stays the source
/// of truth; this only makes sure the schema reflects the prompts the app is
/// actually using.
enum PromptSeeder {
    @MainActor
    static func seedPrompts(in modelContext: ModelContext) throws {
        let templates = [
            PromptTemplate.dailyShortSummary,
            PromptTemplate.dailyLongSummary,
            PromptTemplate.weeklyInsights,
        ]
        let existing = try modelContext.fetch(FetchDescriptor<PromptRecord>())
        var didInsert = false

        for template in templates
        where !existing.contains(where: { $0.text == template.text }) {
            modelContext.insert(PromptRecord(prompt: Prompt(text: template.text)))
            didInsert = true
        }

        if didInsert {
            try modelContext.save()
        }
    }
}
