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
        #expect(path.hasSuffix(".txt"))
    }

    @Test @MainActor
    func insightsGenerationUsesAClampedFourteenDayRange() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let calendar = testCalendar
        let today = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))
        )
        let patient = PatientProfile(name: "Taylor")
        try await store.savePatientProfile(patient)
        try await store.saveDiaryEntry(
            DiaryEntry(
                patientID: patient.id,
                day: today,
                promptText: "Prompt",
                summaryShort: "A steady day"
            )
        )
        let model = InsightsViewModel(
            noteStore: store,
            healthModel: StubHealthLanguageModel(),
            calendar: calendar,
            now: today
        )

        let tooEarly = try #require(
            calendar.date(byAdding: .day, value: -30, to: today)
        )
        model.setFromDate(tooEarly)
        #expect(
            calendar.dateComponents(
                [.day],
                from: model.fromDate,
                to: model.toDate
            ).day == 14
        )

        await model.generateInsight()
        #expect(model.generatedInsight?.generatedFrom == model.fromDate)
        #expect(model.generatedInsight?.generatedTo == model.toDate)
        // The range the user picked reaches the prompt, and the filled prompt
        // is what gets persisted.
        #expect(model.generatedInsight?.promptText.contains("18 September") == true)
        #expect(try await store.insights().count == 1)
    }

    @Test @MainActor
    func demoDataSeederCreatesEntriesOnce() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let context = container.mainContext
        let store = SwiftDataNoteStore(modelContext: context)

        try PatientSeeder.seedIfNeeded(in: context)
        try DemoDataSeeder.seedIfNeeded(in: context)
        let patient = try #require(await store.patientProfiles().first)
        #expect(try await store.diaryEntries(patientID: patient.id).count == 11)
        let insights = try await store.insights()
        #expect(insights.count == 1)
        #expect(insights.first?.text.contains("sleep and energy") == true)
        #expect(patient.age == 29)
        #expect(patient.email == "magnus.ross@example.com")
        #expect(try await store.questions(patientID: patient.id).count == 8)
        let reminder = try #require(patient.dailyReminder)
        #expect(Calendar.autoupdatingCurrent.component(.hour, from: reminder) == 21)

        try DemoDataSeeder.seedIfNeeded(in: context)
        #expect(try await store.diaryEntries(patientID: patient.id).count == 11)
        #expect(try await store.insights().count == 1)
    }

    @Test
    func promptTemplateFillsBothPlaceholders() {
        let profile = PatientProfile(
            name: "Taylor",
            age: 29,
            weight: 68,
            gender: "Non-binary",
            healthInterests: ["Sleep", "Energy"],
            healthConcerns: ["Headaches"],
            email: "taylor@example.com"
        )

        let filled = PromptTemplate.dailyShortSummary.filled(
            transcript: "  I slept badly and felt flat.  ",
            profile: profile
        )

        #expect(!filled.contains(PromptTemplate.transcriptPlaceholder))
        #expect(!filled.contains(PromptTemplate.profilePlaceholder))
        #expect(filled.contains("TRANSCRIPT: I slept badly and felt flat."))
        #expect(filled.contains("Age: 29"))
        #expect(filled.contains("Weight: 68 kg"))
        #expect(filled.contains("Health interests: Sleep Energy"))
        // The email tells the model nothing about the patient's health.
        #expect(!filled.contains("taylor@example.com"))
    }

    @Test
    func insightsPromptFillsThePeriodAndTheDays() {
        let filled = PromptTemplate.weeklyInsights.filled(
            period: "7 to 13 September",
            dailySummaries: ["User reports poor sleep.", "User reports knee pain."]
        )

        #expect(!filled.contains(PromptTemplate.periodPlaceholder))
        #expect(!filled.contains(PromptTemplate.dailySummariesPlaceholder))
        #expect(filled.contains("NOTES (7 to 13 September):"))
        #expect(filled.contains("User reports poor sleep.\nUser reports knee pain."))
    }

    @Test @MainActor
    func patientSeederCreatesTheProfileAndItsQuestions() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let context = container.mainContext
        let store = SwiftDataNoteStore(modelContext: context)

        try PatientSeeder.seedIfNeeded(in: context)
        let patient = try #require(await store.patientProfiles().first)
        #expect(patient.name == "Magnus Ross")
        #expect(patient.age == 29)
        #expect(patient.weight == 75)
        #expect(patient.gender == "male")
        #expect(patient.healthConcerns.first?.contains("bad knee from running") == true)

        // NoteStore sorts questions by text, so compare the set rather than
        // the seeder's order.
        let questions = try await store.questions(patientID: patient.id)
        #expect(questions.map(\.text).sorted() == PatientSeeder.questionTexts.sorted())

        // Seeding again leaves one patient and one set of questions.
        try PatientSeeder.seedIfNeeded(in: context)
        #expect(try await store.patientProfiles().count == 1)
        #expect(try await store.questions(patientID: patient.id).count == 8)
    }

    @Test @MainActor
    func promptSeederStoresBothTemplatesOnce() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let context = container.mainContext
        let store = SwiftDataNoteStore(modelContext: context)

        try PromptSeeder.seedPrompts(in: context)
        try PromptSeeder.seedPrompts(in: context)

        let texts = try await store.prompts().map(\.text)
        #expect(texts.count == 3)
        #expect(texts.contains(PromptTemplate.dailyShortSummary.text))
        #expect(texts.contains(PromptTemplate.dailyLongSummary.text))
        #expect(texts.contains(PromptTemplate.weeklyInsights.text))
    }

    @Test
    func profileDescriptionOmitsFieldsThePatientDidNotGive() {
        let sparse = PatientProfile(name: "Sam")

        let description = sparse.promptDescription

        #expect(description == "Name: Sam")
        #expect(!description.contains("Age"))
        #expect(!description.contains("Weight"))
        #expect(PatientProfile(name: "").promptDescription
            == "No profile details were given.")
    }

    @Test
    func summaryTextStripsWhatTheModelWrapsAroundASentence() {
        let expected = "I slept badly and woke twice."

        #expect(SummaryText.clean(expected) == expected)
        #expect(SummaryText.clean("  \(expected)\n\n") == expected)
        #expect(SummaryText.clean("\"\(expected)\"") == expected)
        #expect(SummaryText.clean("Short summary: \(expected)") == expected)
        #expect(SummaryText.clean("short_summary: \"\(expected)\"") == expected)
        #expect(SummaryText.clean("```\n\(expected)\n```") == expected)
    }

    @Test
    func summaryTextLeavesAPartialSentenceAlone() {
        // Mid-stream: the opening quote goes so the screen never shows one, and
        // the unfinished words are left exactly as they arrived.
        #expect(SummaryText.clean("\"I slept badly and") == "I slept badly and")
        #expect(SummaryText.clean("I slept") == "I slept")
        #expect(SummaryText.clean("") == "")
        // A quotation the user actually made is not a wrapper.
        #expect(
            SummaryText.clean("I told them \"I am fine\" and left.")
                == "I told them \"I am fine\" and left."
        )
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

/// Stands in for the model so the view model's own behaviour can be tested
/// without a 2.5 GB download.
private final class StubHealthLanguageModel: HealthLanguageModel {
    func prepare() async {}

    func generateShortSummary(
        transcript: String,
        profile: PatientProfile,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        onPartial?("I had a")
        return GeneratedText(text: "I had a steady day.", promptText: "short prompt")
    }

    func generateLongSummary(
        transcript: String,
        profile: PatientProfile
    ) async throws -> GeneratedText {
        GeneratedText(text: "User reports a steady day.", promptText: "long prompt")
    }

    func generateInsights(
        from entries: [DiaryEntry],
        period: String,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        onPartial?("You seem")
        GeneratedText(
            text: "You seem steadier at weekends.",
            promptText: "insights prompt for \(period)"
        )
    }
}
