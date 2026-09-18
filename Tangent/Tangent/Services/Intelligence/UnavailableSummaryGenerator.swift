import Foundation

/// Used where MLX cannot run — the Simulator, and previews. Fails cleanly so
/// the rest of the app behaves exactly as it would on a device without the
/// model, rather than crashing inside Metal.
final class UnavailableSummaryGenerator: SummaryGenerator {
    func generateSummary(
        transcript: String,
        profile: PatientProfile,
        template: SummaryPromptTemplate,
        onProgress: (@Sendable (Int) -> Void)?
    ) async throws -> GeneratedSummary {
        throw SummaryGenerationError.unsupportedDevice
    }
}
