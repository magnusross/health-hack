import Foundation
import Testing
@testable import Tangent

struct TangentTests {
    @Test @MainActor
    func noteStoreCRUD() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let patientID = UUID()

        var profile = PatientProfile(id: patientID, name: "Sam")
        try await store.savePatientProfile(profile)
        #expect(try await store.patientProfile(id: patientID)?.name == "Sam")
        profile.name = "Alex"
        try await store.savePatientProfile(profile)
        #expect(try await store.patientProfile(id: patientID)?.name == "Alex")

        var prompt = Prompt(text: "How are you feeling?")
        try await store.savePrompt(prompt)
        prompt.text = "How have you felt today?"
        try await store.savePrompt(prompt)
        #expect(try await store.prompt(id: prompt.id)?.text == prompt.text)

        var question = Question(
            patientID: patientID,
            promptText: "Question prompt for Alex",
            text: "How was your energy?"
        )
        try await store.saveQuestion(question)
        question.text = "How was your energy today?"
        try await store.saveQuestion(question)
        #expect(try await store.questions(patientID: patientID) == [question])

        var diary = DiaryEntry(
            patientID: patientID,
            day: Date(),
            questions: [DiaryQuestion(text: question.text)],
            promptText: "Diary prompt for Alex"
        )
        try await store.saveDiaryEntry(diary)
        diary.summaryShort = "Energy was steady."
        try await store.saveDiaryEntry(diary)
        let savedDiary = try #require(
            await store.diaryEntry(id: diary.id)
        )
        #expect(savedDiary.summaryShort == diary.summaryShort)
        #expect(savedDiary.questions == diary.questions)
        #expect(savedDiary.promptText == diary.promptText)

        var insight = Insight(
            day: Date(),
            generatedFrom: diary.day,
            generatedTo: diary.day,
            promptText: "Insight prompt for Alex",
            text: "No trend yet."
        )
        try await store.saveInsight(insight)
        insight.text = "Energy appears steady."
        try await store.saveInsight(insight)
        #expect(try await store.insight(id: insight.id)?.text == insight.text)

        try await store.deleteInsight(id: insight.id)
        try await store.deleteDiaryEntry(id: diary.id)
        try await store.deleteQuestion(id: question.id)
        try await store.deletePrompt(id: prompt.id)
        try await store.deletePatientProfile(id: profile.id)

        #expect(try await store.insights().isEmpty)
        #expect(try await store.diaryEntries(patientID: nil).isEmpty)
        #expect(try await store.questions(patientID: nil).isEmpty)
        #expect(try await store.prompts().isEmpty)
        #expect(try await store.patientProfiles().isEmpty)
    }

    @Test
    func diaryTimelineIncludesMissingDaysAndEmptyToday() throws {
        let calendar = testCalendar
        let patientID = UUID()
        let today = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))
        )
        let twelfth = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))
        )
        let thirteenth = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 13))
        )
        let entries = [
            DiaryEntry(
                patientID: patientID,
                day: twelfth,
                promptText: "Prompt",
                summaryShort: "First entry"
            ),
            DiaryEntry(
                patientID: patientID,
                day: thirteenth,
                promptText: "Prompt",
                summaryShort: "Second entry"
            )
        ]

        let days = DiaryHomeViewModel.makeTimeline(
            entries: entries,
            today: today,
            calendar: calendar
        )

        #expect(days.count == 4)
        #expect(days[0].entry?.summaryShort == "First entry")
        #expect(days[1].entry?.summaryShort == "Second entry")
        #expect(days[2].entry == nil)
        #expect(days[3].entry == nil)
    }

    @Test
    func diaryTimelineShowsCompletedToday() throws {
        let calendar = testCalendar
        let patientID = UUID()
        let today = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))
        )
        let entry = DiaryEntry(
            patientID: patientID,
            day: today,
            promptText: "Prompt",
            summaryShort: "Today is complete"
        )

        let days = DiaryHomeViewModel.makeTimeline(
            entries: [entry],
            today: today,
            calendar: calendar
        )

        #expect(days.count == 1)
        #expect(days[0].entry?.id == entry.id)
    }

    @Test
    func emptyDiaryTimelineOnlyShowsToday() throws {
        let calendar = testCalendar
        let today = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))
        )

        let days = DiaryHomeViewModel.makeTimeline(
            entries: [],
            today: today,
            calendar: calendar
        )

        #expect(days == [DiaryTimelineDay(date: today, entry: nil)])
    }

    @Test
    func diaryXMLExportIncludesAllFieldsAndEscapesText() throws {
        let patientID = UUID()
        let questionID = UUID()
        let entryID = UUID()
        let entry = DiaryEntry(
            id: entryID,
            patientID: patientID,
            day: Date(timeIntervalSince1970: 100),
            questions: [DiaryQuestion(id: questionID, text: "Pain < 3 & improving")],
            promptText: "Ask \"carefully\"",
            summaryShort: "Better",
            summaryLong: "It's a better day.",
            transcriptPath: "/private/tangent/audio.m4a"
        )

        let data = DiaryXMLExporter.makeDocument(
            entries: [entry],
            patientID: patientID,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let xml = try #require(String(data: data, encoding: .utf8))

        #expect(xml.contains("patient-id=\"\(patientID.uuidString)\""))
        #expect(xml.contains("<entry id=\"\(entryID.uuidString)\">"))
        #expect(xml.contains("<question id=\"\(questionID.uuidString)\">Pain &lt; 3 &amp; improving</question>"))
        #expect(xml.contains("<prompt-text>Ask &quot;carefully&quot;</prompt-text>"))
        #expect(xml.contains("<summary-short>Better</summary-short>"))
        #expect(xml.contains("<summary-long>It&apos;s a better day.</summary-long>"))
        #expect(xml.contains("<transcript-path>/private/tangent/audio.m4a</transcript-path>"))
    }

    @Test
    func dailyDetailsLoadsTranscriptFromStoredPath() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "tangent-transcript-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try "  I felt rested after my walk.\n".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        #expect(
            DailyTangentDetailsViewModel.loadTranscript(at: url.path)
                == "I felt rested after my walk."
        )
        #expect(
            DailyTangentDetailsViewModel.loadTranscript(at: "") == nil
        )
        #expect(
            DailyTangentDetailsViewModel.loadTranscript(
                at: "/tmp/tangent-audio.m4a"
            ) == nil
        )
    }

    @Test
    func recordingWritesTranscriptTextFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "tangent-transcripts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcript = "I slept well. My energy stayed steady all day."

        let path = try RecordHomeViewModel.writeTranscript(
            transcript,
            directory: directory
        )

        #expect(try String(contentsOfFile: path, encoding: .utf8) == transcript)
        #expect(RecordHomeViewModel.summarize(transcript) == "I slept well.")
        #expect(path.hasSuffix(".txt"))
    }

    @Test @MainActor
    func demoDataSeederCreatesEntriesOnce() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let context = container.mainContext
        let store = SwiftDataNoteStore(modelContext: context)

        try DemoDataSeeder.seedIfNeeded(in: context)
        let patient = try #require(await store.patientProfiles().first)
        #expect(try await store.diaryEntries(patientID: patient.id).count == 11)
        let insights = try await store.insights()
        #expect(insights.count == 1)
        #expect(insights.first?.text.contains("sleep and energy") == true)
        #expect(patient.age == 29)
        #expect(patient.email == "taylor@example.com")
        let reminder = try #require(patient.dailyReminder)
        #expect(Calendar.autoupdatingCurrent.component(.hour, from: reminder) == 21)

        try DemoDataSeeder.seedIfNeeded(in: context)
        #expect(try await store.diaryEntries(patientID: patient.id).count == 11)
        #expect(try await store.insights().count == 1)
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
