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

/// Turns a transcript into a diary summary on device.
///
/// Implementations must be safe to call off the main actor, must not hold any
/// state between calls, and must honour task cancellation.
protocol SummaryGenerator: AnyObject, Sendable {
    /// - Parameter onShortSummary: the short summary as it is written, so the
    ///   screen can show it filling in. The long summary follows it and keeps
    ///   generating after this stops changing.
    func generateSummary(
        transcript: String,
        profile: PatientProfile,
        template: SummaryPromptTemplate,
        onShortSummary: (@Sendable (String) -> Void)?
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
