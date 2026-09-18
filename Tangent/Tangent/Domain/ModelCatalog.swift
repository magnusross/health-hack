import Foundation

enum ModelDownloadState: Equatable, Sendable {
    case notDownloaded
    case downloading(fraction: Double)
    case ready(bytesOnDisk: Int64)
    case failed(message: String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

/// Owns which model Tangent summarises with, and the weights on disk.
///
/// Settings talks to this and nothing else. Downloads are always started by the
/// user: nothing here reaches the network on its own.
@MainActor
protocol ModelCatalog: AnyObject {
    /// The model summaries are generated with. Persisted across launches.
    var selectedModel: SummaryModelID { get }

    func select(_ model: SummaryModelID)

    /// Reads the real state from disk rather than a cached flag, so a model
    /// deleted behind the app's back is reported honestly.
    func state(of model: SummaryModelID) async -> ModelDownloadState

    /// Downloads the weights, reporting completed fraction as it goes.
    func download(
        _ model: SummaryModelID,
        onProgress: @escaping @MainActor (Double) -> Void
    ) async throws

    func cancelDownload(_ model: SummaryModelID)

    func delete(_ model: SummaryModelID) async throws
}
