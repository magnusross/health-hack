import SwiftUI

struct ContentView: View {
    let dependencies: AppDependencies

    @State private var selectedTab = PrimaryTab.diary
    @State private var diaryPath: [DiaryRoute] = []
    @State private var recordPath: [RecordRoute] = []
    @State private var coversRecordTransition = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $diaryPath) {
                DiaryHomeView(
                    noteStore: dependencies.noteStore,
                    openEntry: { diaryPath.append(.details($0)) },
                    openRecord: { selectedTab = .record },
                    openSettings: { diaryPath.append(.settings) }
                )
                .navigationDestination(for: DiaryRoute.self) { route in
                    switch route {
                    case .details(let diaryID):
                        DailyTangentDetailsView(
                            noteStore: dependencies.noteStore,
                            transcriber: dependencies.transcriber,
                            summaryGenerator: dependencies.summaryGenerator,
                            diaryID: diaryID,
                            redoToday: startNewRecording,
                            openSettings: { diaryPath.append(.settings) }
                        )
                    case .freshRecording(let diaryID):
                        DailyTangentDetailsView(
                            noteStore: dependencies.noteStore,
                            transcriber: dependencies.transcriber,
                            summaryGenerator: dependencies.summaryGenerator,
                            diaryID: diaryID,
                            streamsTranscript: true,
                            redoToday: startNewRecording,
                            openSettings: { diaryPath.append(.settings) }
                        )
                    case .settings:
                        SettingsView(
                            noteStore: dependencies.noteStore,
                            reminderScheduler: dependencies.reminderScheduler,
                            modelCatalog: dependencies.modelCatalog
                        )
                    }
                }
            }
            .tabItem {
                Image(systemName: "book.closed")
                    .accessibilityLabel("Diary")
            }
            .tag(PrimaryTab.diary)

            NavigationStack(path: $recordPath) {
                RecordHomeView(
                    audioRecorder: dependencies.audioRecorder,
                    transcriber: dependencies.transcriber,
                    noteStore: dependencies.noteStore,
                    summaryGenerator: dependencies.summaryGenerator,
                    openSettings: { recordPath.append(.settings) },
                    onRecordingFinished: showDailySummary(for:)
                )
                .navigationDestination(for: RecordRoute.self) { route in
                    switch route {
                    case .settings:
                        SettingsView(
                            noteStore: dependencies.noteStore,
                            reminderScheduler: dependencies.reminderScheduler,
                            modelCatalog: dependencies.modelCatalog
                        )
                    }
                }
            }
            .tabItem {
                Image(systemName: "mic")
                    .accessibilityLabel("Record")
            }
            .tag(PrimaryTab.record)

            NavigationStack {
                InsightsView(noteStore: dependencies.noteStore)
            }
            .tabItem {
                Image(systemName: "lightbulb")
                    .accessibilityLabel("Insights")
            }
            .tag(PrimaryTab.insights)
        }
        .tint(Color.tangentPurple)
        .overlay {
            Color.tangentWash
                .ignoresSafeArea()
                .opacity(coversRecordTransition ? 1 : 0)
                .allowsHitTesting(coversRecordTransition)
        }
        .animation(.easeInOut(duration: 0.45), value: coversRecordTransition)
        .animation(.easeInOut(duration: 0.45), value: selectedTab)
    }

    private func showDailySummary(for diaryID: UUID) {
        coversRecordTransition = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            recordPath = []
            diaryPath = [.freshRecording(diaryID)]
            selectedTab = .diary
            try? await Task.sleep(for: .milliseconds(60))
            coversRecordTransition = false
        }
    }

    private func startNewRecording() {
        diaryPath = []
        recordPath = []
        selectedTab = .record
    }
}

private enum PrimaryTab: Hashable {
    case diary
    case record
    case insights
}

private enum DiaryRoute: Hashable {
    case details(UUID)
    case freshRecording(UUID)
    case settings
}


private enum RecordRoute: Hashable {
    case settings
}

#Preview {
    let container = try! TangentModelContainer.make(inMemory: true)
    ContentView(
        dependencies: AppDependencies(
            noteStore: SwiftDataNoteStore(modelContext: container.mainContext),
            audioRecorder: UnavailableAudioRecorder(),
            transcriber: UnavailableTranscriber(),
            reminderScheduler: UnavailableReminderScheduler(),
            summaryGenerator: UnavailableSummaryGenerator(),
            modelCatalog: MLXModelCatalog()
        )
    )
}
