import Foundation

/// Used where MLX cannot run — the Simulator, and previews. Fails cleanly so
/// the rest of the app behaves exactly as it would on a device without the
/// model, rather than crashing inside Metal.
final class UnavailableHealthLanguageModel: HealthLanguageModel {
    func prepare() async {}

    func generateShortSummary(
        transcript: String,
        profile: PatientProfile,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        throw HealthLanguageModelError.unsupportedDevice
    }

    func generateInsights(
        from summaries: [DiarySummary],
        period: String,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        throw HealthLanguageModelError.unsupportedDevice
    }
}
