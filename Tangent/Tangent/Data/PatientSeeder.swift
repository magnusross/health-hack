import Foundation
import SwiftData

/// Creates the patient and their standing questions.
///
/// Unlike `DemoDataSeeder` this runs in every build: there is no onboarding
/// yet, and without a profile the app cannot save a Tangent at all.
enum PatientSeeder {
    @MainActor
    static func seedIfNeeded(in modelContext: ModelContext) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<PatientProfileRecord>(sortBy: [SortDescriptor(\.name)])
        )

        let record: PatientProfileRecord
        if let first = existing.first {
            // The reminder is the patient's own setting, so it survives a
            // refresh of the seeded details.
            record = first
            record.update(from: profile(id: first.id, reminder: first.dailyReminder))
        } else {
            record = PatientProfileRecord(
                profile: profile(id: UUID(), reminder: defaultReminder)
            )
            modelContext.insert(record)
        }

        try seedQuestions(for: record.id, in: modelContext)
        try modelContext.save()
    }

    static let questionTexts = [
        "How did you sleep last night?",
        "How stressed have you felt today, from 1 to 10?",
        "How has your knee been feeling today?",
        "Did you get any exercise today?",
        "What did you eat and drink today?",
        "How has your mood been today?",
        "Did you have any takeaways or late-night snacks today?",
        "Is there anything else about your health you'd like to mention?",
    ]

    private static func profile(id: UUID, reminder: Date?) -> PatientProfile {
        PatientProfile(
            id: id,
            name: "Magnus Ross",
            age: 29,
            weight: 75,
            gender: "male",
            healthInterests: [
                """
                I want to sleep better and get into a healthier routine with my \
                eating, fewer takeaways and less snacking late at night.
                """
            ],
            healthConcerns: [
                """
                Work has been really stressful lately and I find it hard to \
                switch off in the evenings. I've also got a bad knee from \
                running, it aches after longer runs and I've had to cut back, \
                which isn't helping with the stress.
                """
            ],
            email: "magnus.ross@example.com",
            dailyReminder: reminder
        )
    }

    private static var defaultReminder: Date? {
        Calendar.autoupdatingCurrent.date(
            bySettingHour: 21,
            minute: 0,
            second: 0,
            of: Date()
        )
    }

    /// Replaces the stored questions whenever they no longer match the ones in
    /// the app, so a device follows the code rather than whatever it was first
    /// launched with.
    private static func seedQuestions(
        for patientID: UUID,
        in modelContext: ModelContext
    ) throws {
        let stored = try modelContext
            .fetch(FetchDescriptor<QuestionRecord>())
            .filter { $0.patientID == patientID }

        guard stored.map(\.text) != questionTexts else { return }

        for question in stored {
            modelContext.delete(question)
        }
        for text in questionTexts {
            modelContext.insert(
                QuestionRecord(
                    question: Question(
                        patientID: patientID,
                        promptText: "",
                        text: text
                    )
                )
            )
        }
    }
}
