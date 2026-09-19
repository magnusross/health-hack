import Combine
import Foundation

/// Gates every model entry point, including calls already in progress when AI is disabled.
@MainActor
final class OptionalAIService: DiaryLanguageModel, ModelCatalog {
    private let preferences: AppPreferences
    private let languageModel: any DiaryLanguageModel
    private let catalog: any ModelCatalog
    private var observation: AnyCancellable?
    private var cancellations: [UUID: () -> Void] = [:]
    private var revision = 0

    init(preferences: AppPreferences, languageModel: any DiaryLanguageModel, catalog: any ModelCatalog) {
        self.preferences = preferences
        self.languageModel = languageModel
        self.catalog = catalog
        observation = preferences.$aiEnabled.removeDuplicates().sink { [weak self] enabled in
            guard !enabled, let self else { return }
            self.revision += 1
            for cancel in self.cancellations.values { cancel() }
            for model in SummaryModelID.allCases { self.catalog.cancelDownload(model) }
        }
    }

    func prepare() async {
        try? await run { [languageModel] in await languageModel.prepare() }
    }

    func generateShortSummary(
        transcript: String, profile: UserProfile,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        try await requireDownloadedModel()
        return try await run { [languageModel] in
            try await languageModel.generateShortSummary(
                transcript: transcript, profile: profile, onPartial: onPartial
            )
        }
    }

    func generateInsights(
        from summaries: [DiarySummary], focus: DiaryFocus, period: String,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        try await requireDownloadedModel()
        return try await run { [languageModel] in
            try await languageModel.generateInsights(
                from: summaries, focus: focus, period: period, onPartial: onPartial
            )
        }
    }

    var selectedModel: SummaryModelID { catalog.selectedModel }

    func select(_ model: SummaryModelID) {
        guard preferences.aiEnabled else { return }
        catalog.select(model)
    }

    func state(of model: SummaryModelID) async -> ModelDownloadState {
        await catalog.state(of: model)
    }

    func download(_ model: SummaryModelID, onProgress: @escaping @MainActor (DownloadProgress) -> Void) async throws {
        try await run { [catalog] in
            try await catalog.download(model, onProgress: onProgress)
        }
    }

    func cancelDownload(_ model: SummaryModelID) { catalog.cancelDownload(model) }
    func delete(_ model: SummaryModelID) async throws { try await catalog.delete(model) }

    private func requireDownloadedModel() async throws {
        guard preferences.aiEnabled else { throw DiaryLanguageModelError.aiDisabled }
        let selected = catalog.selectedModel
        guard await catalog.state(of: selected).isReady else {
            throw DiaryLanguageModelError.modelNotDownloaded(selected)
        }
    }

    private func run<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        guard preferences.aiEnabled else { throw DiaryLanguageModelError.aiDisabled }
        try Task.checkCancellation()
        let startedAt = revision
        let id = UUID()
        let task = Task {
            try Task.checkCancellation()
            return try await operation()
        }
        cancellations[id] = { task.cancel() }
        defer { cancellations[id] = nil }
        return try await withTaskCancellationHandler {
            let value = try await task.value
            try Task.checkCancellation()
            guard preferences.aiEnabled, startedAt == revision else { throw CancellationError() }
            return value
        } onCancel: {
            task.cancel()
        }
    }
}
