import Foundation
import SwiftData

enum DemoDataSeeder {
    @MainActor
    static func seedIfNeeded(in modelContext: ModelContext) throws {
        #if DEBUG
        // The patient is seeded in every build by `PatientSeeder`; this only
        // adds demo history on top of them.
        guard let profile = try modelContext.fetch(
            FetchDescriptor<PatientProfileRecord>(sortBy: [SortDescriptor(\.name)])
        ).first else {
            return
        }

        let existingQuestions = try modelContext.fetch(
            FetchDescriptor<QuestionRecord>()
        ).filter { $0.patientID == profile.id }
        if existingQuestions.isEmpty {
            let questions = [
                "What felt most noticeable in your body today?",
                "Was there a moment when your energy changed?",
                "What has been sitting on your mind?",
                "Did anything help you feel more at ease?",
                "How did you sleep, and how did that shape your day?",
                "Is there anything you want to remember about today?"
            ]
            for text in questions {
                modelContext.insert(
                    QuestionRecord(
                        question: Question(
                            patientID: profile.id,
                            promptText: "Gentle recording prompt",
                            text: text
                        )
                    )
                )
            }
        }

        let existingEntries = try modelContext.fetch(
            FetchDescriptor<DiaryEntryRecord>()
        )
        let patientEntries = existingEntries.filter { $0.patientID == profile.id }
        let hasRealEntries = patientEntries.contains {
            $0.promptText != Self.demoPrompt
        }
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        if !hasRealEntries {
            for entry in patientEntries {
                modelContext.delete(entry)
            }

            // A couple of empty gaps (including yesterday) so filled vs empty
            // cards stay easy to tell apart. Today stays empty for recording.
            let examples: [(daysAgo: Int, summary: String)] = [
                (14, "I slept restlessly and woke up with a tight neck."),
                (13, "A slow morning, but a walk after lunch lifted my mood."),
                (12, "Stress sat in my chest during work. Evening stretching helped."),
                (10, "I slept more deeply and woke up feeling refreshed."),
                (9, "Energy was steady until late afternoon, then I faded."),
                (8, "A mild headache appeared after lunch but eased by evening."),
                (7, "I drank more water and felt clearer by mid-afternoon."),
                (6, "My shoulders were tense. A short stretch before bed helped."),
                (4, "I felt calmer today and had steady energy throughout the day."),
                (3, "Sleep came easily. I woke up without the usual grogginess."),
                (2, "A little anxious before a meeting, then lighter afterward."),
            ]

            for example in examples {
                guard let day = calendar.date(
                    byAdding: .day,
                    value: -example.daysAgo,
                    to: today
                ) else {
                    continue
                }

                let entry = DiaryEntry(
                    patientID: profile.id,
                    day: day,
                    questions: [
                        DiaryQuestion(text: "How have you been feeling?")
                    ],
                    promptText: Self.demoPrompt,
                    summaryShort: example.summary,
                    summaryLong: example.summary,
                    transcriptPath: try demoTranscriptPath(
                        daysAgo: example.daysAgo,
                        summary: example.summary
                    )
                )
                modelContext.insert(DiaryEntryRecord(entry: entry))
            }
        }

        let existingInsights = try modelContext.fetch(
            FetchDescriptor<InsightRecord>()
        )
        if existingInsights.isEmpty,
           let generatedFrom = calendar.date(
               byAdding: .day,
               value: -14,
               to: today
           ),
           let generatedTo = calendar.date(
               byAdding: .day,
               value: -2,
               to: today
           ) {
            let insight = Insight(
                day: today,
                generatedFrom: generatedFrom,
                generatedTo: generatedTo,
                promptText: Self.demoInsightPrompt,
                text: "Your sleep and energy appear steadier on days when you take a walk or stretch. Headaches have been brief and often improve by the evening."
            )
            modelContext.insert(InsightRecord(insight: insight))
        }

        try modelContext.save()
        #endif
    }

    private static let demoPrompt = "Demo diary prompt for Taylor"
    private static let demoInsightPrompt = "Demo insight prompt for Taylor"

    private static func demoTranscriptPath(
        daysAgo: Int,
        summary: String
    ) throws -> String {
        let directory = URL.applicationSupportDirectory
            .appending(path: "DemoTranscripts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appending(path: "tangent-\(daysAgo)-days-ago.txt")
        let transcript = "Hi. I wanted to check in about today. \(summary) Overall, I am paying attention to how rest, movement, and stress affect how I feel."
        try transcript.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}
