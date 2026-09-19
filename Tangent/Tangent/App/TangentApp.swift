import SwiftData
import SwiftUI

@main
@MainActor
struct TangentApp: App {
    private let modelContainer: ModelContainer
    private let dependencies: AppDependencies

    init() {
        do {
            let modelContainer = try TangentModelContainer.make()
            self.modelContainer = modelContainer
            try ProfileSeeder.seedIfNeeded(
                in: modelContainer.mainContext
            )
            try PromptSeeder.seedPrompts(
                in: modelContainer.mainContext
            )
            try DemoDataSeeder.seedIfNeeded(
                in: modelContainer.mainContext
            )
            dependencies = AppDependencies(
                noteStore: SwiftDataNoteStore(
                    modelContext: modelContainer.mainContext
                ),
                audioRecorder: AVAudioRecorderService(),
                transcriber: OnDeviceTranscriber(),
                languageModel: Self.makeLanguageModel(),
                modelCatalog: MLXModelCatalog(),
                reminderScheduler: LocalReminderScheduler()
            )
        } catch {
            fatalError("Unable to initialize Tangent persistence: \(error)")
        }
    }

    /// MLX needs a Metal GPU, which the simulator does not have. Summaries
    /// then fail cleanly instead of crashing inside Metal.
    private static func makeLanguageModel() -> any DiaryLanguageModel {
        #if targetEnvironment(simulator)
        UnavailableDiaryLanguageModel()
        #else
        MLXDiaryLanguageModel()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
        }
        .modelContainer(modelContainer)
    }
}
