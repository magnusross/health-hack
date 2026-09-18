import SwiftData

enum TangentModelContainer {
    static let schema = Schema([
        PatientProfileRecord.self,
        PromptRecord.self,
        QuestionRecord.self,
        DiaryEntryRecord.self,
        InsightRecord.self
    ])

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
