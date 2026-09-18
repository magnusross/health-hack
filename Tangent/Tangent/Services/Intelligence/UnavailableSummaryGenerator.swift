import Foundation

/// Used where MLX cannot run — the Simulator, and previews. Fails cleanly so
/// the rest of the app behaves exactly as it would on a device without the
/// model, rather than crashing inside Metal.
final class UnavailableSummaryGenerator: SummaryGenerator {
    func prepare() async {}

    func generateShortSummary(
        transcript: String,
        profile: PatientProfile,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        throw SummaryGenerationError.unsupportedDevice
    }

    func generateLongSummary(
        transcript: String,
        profile: PatientProfile
    ) async throws -> GeneratedText {
        throw SummaryGenerationError.unsupportedDevice
    }
}
