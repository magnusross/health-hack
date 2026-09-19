import Foundation
import SwiftData
import Testing
@testable import Tangent

@MainActor
struct OptionalAITests {
    @Test
    func preferencesPersistAndExistingInstallsKeepTheirWorkflow() {
        let suite = "TangentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        #expect(!preferences.aiEnabled)
        #expect(!preferences.onboardingCompleted)
        preferences.completeOnboarding()
        preferences.aiEnabled = true
        let relaunched = AppPreferences(defaults: defaults)
        #expect(relaunched.onboardingCompleted)
        #expect(relaunched.aiEnabled)
        relaunched.aiEnabled = false
        #expect(!AppPreferences(defaults: defaults, existingInstall: true).aiEnabled)
        defaults.removePersistentDomain(forName: suite)
        let upgraded = AppPreferences(defaults: defaults, existingInstall: true)
        #expect(upgraded.aiEnabled)
        #expect(upgraded.onboardingCompleted)
    }

    @Test
    func disabledAIBlocksAllModelWorkButKeepsTranscripts() async throws {
        let suite = "TangentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        let languageModel = ControlledLanguageModel()
        let catalog = SpyModelCatalog()
        let service = OptionalAIService(preferences: preferences, languageModel: languageModel, catalog: catalog)
        await service.prepare()
        await #expect(throws: DiaryLanguageModelError.aiDisabled) {
            try await service.download(.default, onProgress: { _ in })
        }
        await #expect(throws: DiaryLanguageModelError.aiDisabled) {
            try await service.generateInsights(from: [], focus: DiaryFocus(), period: "Today", onPartial: nil)
        }
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let profile = UserProfile(name: "Alex")
        try await store.saveUserProfile(profile)
        let path = try RecordHomeViewModel.writeTranscript("I went for a walk.\nThen I drew a tree.")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let entry = DiaryEntry(profileID: profile.id, day: Date(), promptText: "", transcriptPath: path)
        try await store.saveDiaryEntry(entry)
        let details = DailyTangentDetailsViewModel(noteStore: store, languageModel: service, diaryID: entry.id)
        await details.start()
        #expect(details.transcript == "I went for a walk.\nThen I drew a tree.")
        #expect(try await store.diaryEntry(id: entry.id)?.summaryShort == "")
        #expect(await languageModel.calls == 0)
        #expect(catalog.downloads == 0)
        #expect(DiaryHomeViewModel.transcriptPreview(at: path) == "I went for a walk. Then I drew a tree...")
        #expect(DiaryHomeViewModel.transcriptPreview(at: "/missing.txt") == "Transcript not available")

        preferences.aiEnabled = true
        #expect(catalog.downloads == 0) // Enabling AI retains explicit download consent.
        catalog.downloaded = false
        let diary = DiaryHomeViewModel(noteStore: store, modelCatalog: catalog)
        await diary.load()
        #expect(diary.needsModel)
        await details.regenerate()
        #expect(details.summaryDisplay == .failed(message: DiaryLanguageModelError.modelNotDownloaded(.default).localizedDescription, needsModel: true))
        #expect(await languageModel.calls == 0)
        catalog.downloaded = true
        await diary.load()
        #expect(!diary.needsModel)
        await details.regenerate()
        #expect(try await store.diaryEntry(id: entry.id)?.summaryShort == "A walk and a drawing.")
    }

    @Test
    func disablingAIRejectsLateResultsEvenAfterReenabling() async throws {
        let suite = "TangentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.aiEnabled = true
        let languageModel = ControlledLanguageModel(paused: true)
        let catalog = SpyModelCatalog()
        let service = OptionalAIService(preferences: preferences, languageModel: languageModel, catalog: catalog)
        let task = Task {
            try await service.generateShortSummary(transcript: "A walk.", profile: UserProfile(name: "Alex"), onPartial: nil)
        }
        for _ in 0..<1000 {
            if await languageModel.isWaiting { break }
            await Task.yield()
        }
        #expect(await languageModel.isWaiting)
        preferences.aiEnabled = false
        preferences.aiEnabled = true
        await languageModel.resume()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Set(catalog.cancelled) == Set(SummaryModelID.allCases))
    }
}

private actor ControlledLanguageModel: DiaryLanguageModel {
    private(set) var calls = 0
    private let paused: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }

    init(paused: Bool = false) { self.paused = paused }
    func resume() { continuation?.resume(); continuation = nil }
    func prepare() async { calls += 1 }
    func generateShortSummary(transcript: String, profile: UserProfile, onPartial: (@Sendable (String) -> Void)?) async throws -> GeneratedText {
        calls += 1
        if paused { await withCheckedContinuation { continuation = $0 } }
        return GeneratedText(text: "A walk and a drawing.", promptText: "A prompt")
    }
    func generateInsights(from summaries: [DiarySummary], focus: DiaryFocus, period: String, onPartial: (@Sendable (String) -> Void)?) async throws -> GeneratedText {
        calls += 1
        return GeneratedText(text: "Creative afternoons.", promptText: "A prompt")
    }
}

@MainActor
private final class SpyModelCatalog: ModelCatalog {
    var selectedModel = SummaryModelID.default
    var downloaded = true
    var downloads = 0
    var cancelled: [SummaryModelID] = []
    func select(_ model: SummaryModelID) { selectedModel = model }
    func state(of model: SummaryModelID) async -> ModelDownloadState { downloaded ? .ready(bytesOnDisk: 1) : .notDownloaded }
    func download(_ model: SummaryModelID, onProgress: @escaping @MainActor (DownloadProgress) -> Void) async throws { downloads += 1 }
    func cancelDownload(_ model: SummaryModelID) { cancelled.append(model) }
    func delete(_ model: SummaryModelID) async throws {}
}
