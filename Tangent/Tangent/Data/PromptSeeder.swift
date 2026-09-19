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
            PromptTemplate.weeklyInsights,
        ]
        let existing = try modelContext.fetch(FetchDescriptor<PromptRecord>())
        var didChange = false
        for record in existing where record.text == retiredDailySummary.text {
            modelContext.delete(record)
            didChange = true
        }

        for template in templates
        where !existing.contains(where: { $0.text == template.text }) {
            modelContext.insert(PromptRecord(prompt: Prompt(text: template.text)))
            didChange = true
        }

        if didChange {
            try modelContext.save()
        }
    }

    // Migration cleanup for the obsolete built-in prompt. Never used for generation.
    private static let retiredDailySummary = PromptTemplate(
        text: """
        You are a helpful medical assistant. You are summarising one entry in a private
        voice diary.

        Each sentence should be a single fact from the transcript. It should be in passive voice.\u{20}
        Always refer to the user.

        Use the profile below to judge what to foreground. Do not treat anything in it
        as something said in this entry.

        USER PROFILE: {user_profile}

        TRANSCRIPT: {transcript}
        """
    )
}
