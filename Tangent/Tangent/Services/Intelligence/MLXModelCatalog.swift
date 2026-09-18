import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
import Tokenizers

/// Downloads and removes model weights, and remembers which model Tangent
/// summarises with.
///
/// Downloads use MLX's `resolve`, which fetches exactly the files the model
/// factory will later ask for and stops there — nothing is loaded into memory,
/// so Settings never holds 2.5 GB of weights.
@MainActor
final class MLXModelCatalog: ModelCatalog {
    private var downloads: [SummaryModelID: Task<Void, Error>] = [:]
    private var fractions: [SummaryModelID: Double] = [:]

    var selectedModel: SummaryModelID {
        SelectedModelStore.selected
    }

    func select(_ model: SummaryModelID) {
        SelectedModelStore.select(model)
    }

    func state(of model: SummaryModelID) async -> ModelDownloadState {
        if downloads[model] != nil {
            return .downloading(fraction: fractions[model] ?? 0)
        }
        guard ModelStorage.isDownloaded(model) else {
            return .notDownloaded
        }
        return .ready(bytesOnDisk: ModelStorage.bytesOnDisk(model))
    }

    func download(
        _ model: SummaryModelID,
        onProgress: @escaping @MainActor (Double) -> Void
    ) async throws {
        if let existing = downloads[model] {
            return try await existing.value
        }

        fractions[model] = 0
        let task = Task<Void, Error> { [weak self] in
            _ = try await resolve(
                configuration: model.configuration,
                from: #hubDownloader(ModelStorage.client()),
                useLatest: false,
                progressHandler: { progress in
                    // Read off Progress here: it is not Sendable and must not
                    // cross to the main actor.
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in
                        self?.fractions[model] = fraction
                        onProgress(fraction)
                    }
                }
            )
        }
        downloads[model] = task

        defer {
            downloads[model] = nil
            fractions[model] = nil
        }
        try await task.value
    }

    func cancelDownload(_ model: SummaryModelID) {
        downloads[model]?.cancel()
        downloads[model] = nil
        fractions[model] = nil
    }

    /// Deleting the selected model does not change the selection. The next
    /// summary then fails with "not downloaded", which is the truth.
    func delete(_ model: SummaryModelID) async throws {
        cancelDownload(model)
        try ModelStorage.remove(model)
    }
}
