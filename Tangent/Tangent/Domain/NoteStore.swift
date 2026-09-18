import Foundation

@MainActor
protocol NoteStore {
    func savePatientProfile(_ profile: PatientProfile) async throws
    func patientProfile(id: UUID) async throws -> PatientProfile?
    func patientProfiles() async throws -> [PatientProfile]
    func deletePatientProfile(id: UUID) async throws

    func savePrompt(_ prompt: Prompt) async throws
    func prompt(id: UUID) async throws -> Prompt?
    func prompts() async throws -> [Prompt]
    func deletePrompt(id: UUID) async throws

    func saveQuestion(_ question: Question) async throws
    func question(id: UUID) async throws -> Question?
    func questions(patientID: UUID?) async throws -> [Question]
    func deleteQuestion(id: UUID) async throws

    func saveDiaryEntry(_ entry: DiaryEntry) async throws
    func diaryEntry(id: UUID) async throws -> DiaryEntry?
    func diaryEntries(patientID: UUID?) async throws -> [DiaryEntry]
    func deleteDiaryEntry(id: UUID) async throws

    func saveInsight(_ insight: Insight) async throws
    func insight(id: UUID) async throws -> Insight?
    func insights() async throws -> [Insight]
    func deleteInsight(id: UUID) async throws
}
