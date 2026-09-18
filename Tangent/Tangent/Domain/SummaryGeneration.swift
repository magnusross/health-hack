import Foundation

/// Text a model wrote, with the filled prompt that produced it. The prompt is
/// what `DIARY.prompt_text` persists.
struct GeneratedText: Equatable, Sendable {
    var text: String
    var promptText: String

    init(text: String, promptText: String) {
        self.text = text
        self.promptText = promptText
    }
}

/// Turns a transcript into diary summaries on device.
///
/// The two summaries are separate calls rather than one structured reply. The
/// short one is all the user waits for, so it is asked for on its own and comes
/// back in seconds; the long one is for insights and finishes in its own time.
///
/// Implementations must be safe to call off the main actor, must not hold any
/// state between calls, and must honour task cancellation.
protocol SummaryGenerator: AnyObject, Sendable {
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
        profile: PatientProfile,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText

    func generateLongSummary(
        transcript: String,
        profile: PatientProfile
    ) async throws -> GeneratedText
}

enum SummaryGenerationError: LocalizedError, Equatable {
    /// No Metal GPU, so no on-device inference. The Simulator lands here.
    case unsupportedDevice
    case modelNotDownloaded(SummaryModelID)
    case modelLoadFailed(String)
    /// The model answered with nothing usable.
    case unusableOutput
    case emptyTranscript
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
        case .cancelled:
            "Summary generation was cancelled."
        }
    }
}
