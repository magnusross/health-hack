import Foundation
import SwiftData

/// Creates a neutral profile once; existing preferences always belong to the user.
enum ProfileSeeder {
    @MainActor
    static func seedIfNeeded(in modelContext: ModelContext) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<UserProfileRecord>(sortBy: [SortDescriptor(\.name)])
        )
        let profile: UserProfileRecord
        if let first = existing.first {
            profile = first
        } else {
            profile = UserProfileRecord(profile: UserProfile(name: "You"))
            modelContext.insert(profile)
        }
        let questions = try modelContext.fetch(FetchDescriptor<QuestionRecord>())
            .filter { $0.profileID == profile.id }
        if questions.isEmpty {
            for text in questionTexts {
                modelContext.insert(QuestionRecord(question: Question(
                    profileID: profile.id, promptText: "", text: text
                )))
            }
        }
        try modelContext.save()
    }

    static let questionTexts = [
        "What stood out to you today?",
        "What did you spend time on or learn?",
        "What went well, and what felt difficult?",
        "What would you like to explore or change next?",
    ]
}
