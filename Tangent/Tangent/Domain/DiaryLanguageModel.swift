import Foundation

/// Text a model wrote, with the filled prompt that produced it. The prompt is
/// what `prompt_text` persists on whichever row used it.
struct GeneratedText: Equatable, Sendable {
    var text: String
    var promptText: String

    init(text: String, promptText: String) {
        self.text = text
        self.promptText = promptText
    }
}

/// Everything Tangent asks a language model for, all of it on device.
///
/// Generates one short summary per entry and insights from saved short summaries.
/// Implementations must be safe to call off the main actor and honour cancellation.
protocol DiaryLanguageModel: AnyObject, Sendable {
    /// Loads the selected model into memory if its weights are on disk.
    ///
    /// Called when a recording starts so the wait after transcription is
    /// generation alone, not a cold model load. Best effort: a failure here is
    /// silent and surfaces later, when a summary is actually asked for.
    func prepare() async

    /// - Parameter onPartial: the sentence as it is written, so the screen can
    ///   show it filling in.
    func generateShortSummary(
        transcript: String,
        profile: UserProfile,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText

    /// Receives dates and short summaries and reflection interests, with no transcript access.
    func generateInsights(
        from summaries: [DiarySummary],
        focus: DiaryFocus,
        period: String,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText
}

enum DiaryLanguageModelError: LocalizedError, Equatable {
    /// No Metal GPU, so no on-device inference. The Simulator lands here.
    case unsupportedDevice
    case modelNotDownloaded(SummaryModelID)
    case modelLoadFailed(String)
    /// The model answered with nothing usable.
    case unusableOutput
    case emptyTranscript
    case notEnoughEntries
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice:
            "Summaries need a real device. The simulator cannot run the model."
        case .modelNotDownloaded(let model):
            "\(model.displayName) has not been downloaded yet."
        case .modelLoadFailed(let reason):
            "The model could not be loaded. \(reason)"
        case .unusableOutput:
            "The model did not return a usable summary."
        case .emptyTranscript:
            "There is nothing to summarise yet."
        case .notEnoughEntries:
            "There are no summaries in this range to look back over."
        case .cancelled:
            "Summary generation was cancelled."
        }
    }
}
