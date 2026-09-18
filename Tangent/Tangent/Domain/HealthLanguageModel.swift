import Foundation

protocol HealthLanguageModel: AnyObject {
    var isMock: Bool { get }

    func summarize(transcript: String) async throws -> String
    func generateInsights(from entries: [DiaryEntry]) async throws -> String
}
