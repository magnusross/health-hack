import Foundation

/// The language models Tangent can run on device.
///
/// This is deliberately framework free: the MLX configuration and factory for
/// each model live in `Services/Intelligence` so that features, settings and
/// persistence can talk about a model without importing MLX.
enum SummaryModelID: String, CaseIterable, Identifiable, Sendable {
    case gemma3_1B = "gemma3-1b-qat-4bit"
    case medgemma4B = "medgemma-1.5-4b-it-4bit"

    var id: String { rawValue }

    /// The model's own name, used verbatim in the UI.
    var displayName: String {
        switch self {
        case .gemma3_1B: "Gemma 3 1B"
        case .medgemma4B: "MedGemma 4B"
        }
    }

    /// Hugging Face repository holding the 4-bit weights.
    var repoID: String {
        switch self {
        case .gemma3_1B: "mlx-community/gemma-3-1b-it-qat-4bit"
        case .medgemma4B: "mlx-community/medgemma-1.5-4b-it-4bit"
        }
    }

    /// Rough download size, shown before the user commits to it.
    var approximateDownloadBytes: Int64 {
        switch self {
        case .gemma3_1B: 800_000_000
        case .medgemma4B: 2_500_000_000
        }
    }

    static let `default`: SummaryModelID = .gemma3_1B
}
