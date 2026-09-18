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
    private var progresses: [SummaryModelID: DownloadProgress] = [:]

    var selectedModel: SummaryModelID {
        SelectedModelStore.selected
    }

    func select(_ model: SummaryModelID) {
        SelectedModelStore.select(model)
    }

    func state(of model: SummaryModelID) async -> ModelDownloadState {
        if downloads[model] != nil {
            return .downloading(
                progresses[model] ?? DownloadProgress(completedBytes: 0, totalBytes: 0)
            )
        }
        guard ModelStorage.isDownloaded(model) else {
            return .notDownloaded
        }
        return .ready(bytesOnDisk: ModelStorage.bytesOnDisk(model))
    }

    func download(
        _ model: SummaryModelID,
        onProgress: @escaping @MainActor (DownloadProgress) -> Void
    ) async throws {
        if let existing = downloads[model] {
            return try await existing.value
        }

        progresses[model] = DownloadProgress(completedBytes: 0, totalBytes: 0)
        let task = Task<Void, Error> { [weak self] in
            _ = try await resolve(
                configuration: model.configuration,
                from: #hubDownloader(ModelStorage.client()),
                useLatest: false,
                progressHandler: { progress in
                    // Read the counts off Progress here: it is not Sendable and
                    // must not cross to the main actor. The hub weights each
                    // file by its size, so these are bytes.
                    let update = DownloadProgress(
                        completedBytes: progress.completedUnitCount,
                        totalBytes: progress.totalUnitCount
                    )
                    Task { @MainActor in
                        self?.progresses[model] = update
                        onProgress(update)
                    }
                }
            )
        }
        downloads[model] = task

        defer {
            downloads[model] = nil
            progresses[model] = nil
        }
        try await task.value
    }

    func cancelDownload(_ model: SummaryModelID) {
        downloads[model]?.cancel()
        downloads[model] = nil
        progresses[model] = nil
    }

    /// Deleting the selected model does not change the selection. The next
    /// summary then fails with "not downloaded", which is the truth.
    func delete(_ model: SummaryModelID) async throws {
        cancelDownload(model)
        try ModelStorage.remove(model)
    }
}
