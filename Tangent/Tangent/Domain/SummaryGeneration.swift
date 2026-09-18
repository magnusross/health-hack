import Foundation

/// The two summaries a model writes for one diary entry, plus the prompt that
/// produced them. `promptText` is what `DIARY.prompt_text` persists.
struct GeneratedSummary: Equatable, Sendable {
    var short: String
    var long: String
    var promptText: String

    init(short: String, long: String, promptText: String) {
        self.short = short
        self.long = long
        self.promptText = promptText
    }
}

/// A value the model is still writing.
struct StreamedText: Equatable, Sendable {
    var text: String
    /// True once the model has closed the value. The long summary keeps
    /// generating after this, so the screen has to stop claiming the short one
    /// is still being written.
    var isComplete: Bool

    init(text: String, isComplete: Bool) {
        self.text = text
        self.isComplete = isComplete
    }
}

/// Turns a transcript into a diary summary on device.
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

    /// - Parameter onShortSummary: the short summary as it is written, so the
    ///   screen can show it filling in. The long summary follows it and keeps
    ///   generating after this reports itself complete.
    func generateSummary(
        transcript: String,
        profile: PatientProfile,
        template: SummaryPromptTemplate,
        onShortSummary: (@Sendable (StreamedText) -> Void)?
    ) async throws -> GeneratedSummary
}

extension SummaryGenerator {
    func generateSummary(
        transcript: String,
        profile: PatientProfile,
        template: SummaryPromptTemplate = .dailySummary
    ) async throws -> GeneratedSummary {
        try await generateSummary(
            transcript: transcript,
            profile: profile,
            template: template,
            onShortSummary: nil
        )
    }
}

enum SummaryGenerationError: LocalizedError, Equatable {
    /// No Metal GPU, so no on-device inference. The Simulator lands here.
    case unsupportedDevice
    case modelNotDownloaded(SummaryModelID)
    case modelLoadFailed(String)
    /// The model answered, but not with usable JSON, twice.
    case outputNotParseable
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
        case .outputNotParseable:
            "The model did not return a usable summary."
        case .emptyTranscript:
            "There is nothing to summarise yet."
        case .cancelled:
            "Summary generation was cancelled."
        }
    }
}
