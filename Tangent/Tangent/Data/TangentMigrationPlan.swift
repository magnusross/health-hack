import Foundation
import SwiftData

// Frozen schemas keep existing installations readable as storage names evolve.
// Legacy terminology is confined to migration code and never used by features.
enum TangentSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [PatientProfileRecord.self, PromptRecord.self, QuestionRecord.self,
         DiaryEntryRecord.self, InsightRecord.self]
    }

    @Model
    final class PatientProfileRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var age: Int?
        var weight: Double?
        var gender: String
        private var healthInterestsData: Data?
        private var healthConcernsData: Data?
        var email: String
        var dailyReminder: Date?

        var healthInterests: [String] {
            get { StringArrayStorage.decode(healthInterestsData) }
            set { healthInterestsData = StringArrayStorage.encode(newValue) }
        }

        var healthConcerns: [String] {
            get { StringArrayStorage.decode(healthConcernsData) }
            set { healthConcernsData = StringArrayStorage.encode(newValue) }
        }

        init(profile: UserProfile) {
            id = profile.id
            name = profile.name
            age = profile.age
            weight = profile.weight
            gender = profile.gender
            healthInterestsData = StringArrayStorage.encode(profile.interests)
            healthConcernsData = StringArrayStorage.encode(profile.concerns)
            email = profile.email
            dailyReminder = profile.dailyReminder
        }

        func update(from profile: UserProfile) {
            name = profile.name
            age = profile.age
            weight = profile.weight
            gender = profile.gender
            healthInterests = profile.interests
            healthConcerns = profile.concerns
            email = profile.email
            dailyReminder = profile.dailyReminder
        }

        var domainModel: UserProfile {
            UserProfile(
                id: id,
                name: name,
                age: age,
                weight: weight,
                gender: gender,
                interests: healthInterests,
                concerns: healthConcerns,
                email: email,
                dailyReminder: dailyReminder
            )
        }
    }

    private enum StringArrayStorage {
        static func encode(_ strings: [String]) -> Data {
            (try? JSONEncoder().encode(strings)) ?? Data("[]".utf8)
        }

        static func decode(_ data: Data?) -> [String] {
            guard let data else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
    }

    @Model
    final class PromptRecord {
        @Attribute(.unique) var id: UUID
        var text: String

        init(prompt: Prompt) {
            id = prompt.id
            text = prompt.text
        }

        var domainModel: Prompt {
            Prompt(id: id, text: text)
        }
    }

    @Model
    final class QuestionRecord {
        @Attribute(.unique) var id: UUID
        var patientID: UUID
        var promptText: String
        var text: String

        init(question: Question) {
            id = question.id
            patientID = question.profileID
            promptText = question.promptText
            text = question.text
        }

        func update(from question: Question) {
            patientID = question.profileID
            promptText = question.promptText
            text = question.text
        }

        var domainModel: Question {
            Question(
                id: id,
                profileID: patientID,
                promptText: promptText,
                text: text
            )
        }
    }

    @Model
    final class DiaryEntryRecord {
        @Attribute(.unique) var id: UUID
        var patientID: UUID
        var day: Date
        var questions: [DiaryQuestion]
        var promptText: String
        var summaryShort: String
        var transcriptPath: String

        init(entry: DiaryEntry) {
            id = entry.id
            patientID = entry.profileID
            day = entry.day
            questions = entry.questions
            promptText = entry.promptText
            summaryShort = entry.summaryShort
            transcriptPath = entry.transcriptPath
        }

        func update(from entry: DiaryEntry) {
            patientID = entry.profileID
            day = entry.day
            questions = entry.questions
            promptText = entry.promptText
            summaryShort = entry.summaryShort
            transcriptPath = entry.transcriptPath
        }

        var domainModel: DiaryEntry {
            DiaryEntry(
                id: id,
                profileID: patientID,
                day: day,
                questions: questions,
                promptText: promptText,
                summaryShort: summaryShort,
                transcriptPath: transcriptPath
            )
        }
    }

    @Model
    final class InsightRecord {
        @Attribute(.unique) var id: UUID
        var day: Date
        var generatedFrom: Date
        var generatedTo: Date
        var promptText: String
        var text: String

        init(insight: Insight) {
            id = insight.id
            day = insight.day
            generatedFrom = insight.generatedFrom
            generatedTo = insight.generatedTo
            promptText = insight.promptText
            text = insight.text
        }

        func update(from insight: Insight) {
            day = insight.day
            generatedFrom = insight.generatedFrom
            generatedTo = insight.generatedTo
            promptText = insight.promptText
            text = insight.text
        }

        var domainModel: Insight {
            Insight(
                id: id,
                day: day,
                generatedFrom: generatedFrom,
                generatedTo: generatedTo,
                promptText: promptText,
                text: text
            )
        }
    }
}

// The first diary schema also stored a second summary.
enum TangentSchemaV0: VersionedSchema {
    static var versionIdentifier = Schema.Version(0, 9, 0)
    static var models: [any PersistentModel.Type] {
        [TangentSchemaV1.PatientProfileRecord.self, TangentSchemaV1.PromptRecord.self,
         TangentSchemaV1.QuestionRecord.self, DiaryEntryRecord.self, TangentSchemaV1.InsightRecord.self]
    }

    @Model
    final class DiaryEntryRecord {
        @Attribute(.unique) var id: UUID
        var patientID: UUID
        var day: Date
        var questions: [DiaryQuestion]
        var promptText: String
        var summaryShort: String
        var summaryLong: String
        var transcriptPath: String

        init(entry: DiaryEntry) {
            id = entry.id
            patientID = entry.profileID
            day = entry.day
            questions = entry.questions
            promptText = entry.promptText
            summaryShort = entry.summaryShort
            summaryLong = ""
            transcriptPath = entry.transcriptPath
        }
    }
}

enum TangentSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        TangentSchemaV3.models + [TangentSchemaV1.PatientProfileRecord.self]
    }
}

enum TangentSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [UserProfileRecord.self, PromptRecord.self, QuestionRecord.self,
         DiaryEntryRecord.self, InsightRecord.self]
    }
}

enum TangentMigrationPlan: SchemaMigrationPlan {
    private static let legacyQuestionTexts = [
        "How did you sleep last night?",
        "How stressed have you felt today, from 1 to 10?",
        "How has your knee been feeling today?",
        "Did you get any exercise today?",
        "What did you eat and drink today?",
        "How has your mood been today?",
        "Did you have any takeaways or late-night snacks today?",
        "Is there anything else about your health you'd like to mention?",
    ]

    static var schemas: [any VersionedSchema.Type] {
        [TangentSchemaV0.self, TangentSchemaV1.self, TangentSchemaV2.self, TangentSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: TangentSchemaV0.self, toVersion: TangentSchemaV1.self),
            .custom(fromVersion: TangentSchemaV1.self, toVersion: TangentSchemaV2.self,
                    willMigrate: nil, didMigrate: { context in
                let profiles = try context.fetch(FetchDescriptor<TangentSchemaV1.PatientProfileRecord>())
                for profile in profiles {
                    context.insert(UserProfileRecord(profile: profile.domainModel))
                    context.delete(profile)
                }
                // Replace only the old built-in questionnaire, preserving custom questions.
                let questions = try context.fetch(FetchDescriptor<QuestionRecord>())
                for profileID in Set(questions.map(\.profileID)) {
                    let stored = questions.filter { $0.profileID == profileID }
                    if Set(stored.map(\.text)) == Set(legacyQuestionTexts) {
                        stored.forEach { context.delete($0) }
                        for text in ProfileSeeder.questionTexts {
                            context.insert(QuestionRecord(question: Question(
                                profileID: profileID, promptText: "", text: text
                            )))
                        }
                    }
                }
                try context.save()
            }),
            .lightweight(fromVersion: TangentSchemaV2.self, toVersion: TangentSchemaV3.self)
        ]
    }
}
