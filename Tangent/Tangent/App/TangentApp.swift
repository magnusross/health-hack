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
            try PromptSeeder.seedSummaryPrompt(
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
                reminderScheduler: LocalReminderScheduler(),
                summaryGenerator: Self.makeSummaryGenerator(),
                modelCatalog: MLXModelCatalog()
            )
        } catch {
            fatalError("Unable to initialize Tangent persistence: \(error)")
        }
    }

    /// MLX needs a Metal GPU, which the simulator does not have. Summaries
    /// then fail cleanly instead of crashing inside Metal.
    private static func makeSummaryGenerator() -> any SummaryGenerator {
        #if targetEnvironment(simulator)
        UnavailableSummaryGenerator()
        #else
        MLXSummaryGenerator()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
        }
        .modelContainer(modelContainer)
    }
}
