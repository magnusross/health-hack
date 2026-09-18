import Foundation

/// Simulator-safe stand-in for the future on-device MLX language model.
final class MockHealthLanguageModel: HealthLanguageModel {
    let isMock = true

    private let responseDelay: Duration

    init(responseDelay: Duration = .seconds(2)) {
        self.responseDelay = responseDelay
    }

    func summarize(transcript: String) async throws -> String {
        try await Task.sleep(for: responseDelay)
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No reflection was recorded today."
        }
        return "You reflected on how you have been feeling today."
    }

    func generateInsights(from entries: [DiaryEntry]) async throws -> String {
        try await Task.sleep(for: responseDelay)
        guard !entries.isEmpty else {
            return "Record a few Tangents to begin seeing patterns."
        }
        return "Your recent reflections suggest that rest, routine, and energy may be connected."
    }
}
