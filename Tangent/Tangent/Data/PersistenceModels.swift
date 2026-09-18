import Foundation
import SwiftData

@Model
final class PatientProfileRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var age: Int?
    var weight: Double?
    var gender: String
    var healthInterests: [String]
    var healthConcerns: [String]
    var email: String
    var dailyReminder: Date?

    init(profile: PatientProfile) {
        id = profile.id
        name = profile.name
        age = profile.age
        weight = profile.weight
        gender = profile.gender
        healthInterests = profile.healthInterests
        healthConcerns = profile.healthConcerns
        email = profile.email
        dailyReminder = profile.dailyReminder
    }

    func update(from profile: PatientProfile) {
        name = profile.name
        age = profile.age
        weight = profile.weight
        gender = profile.gender
        healthInterests = profile.healthInterests
        healthConcerns = profile.healthConcerns
        email = profile.email
        dailyReminder = profile.dailyReminder
    }

    var domainModel: PatientProfile {
        PatientProfile(
            id: id,
            name: name,
            age: age,
            weight: weight,
            gender: gender,
            healthInterests: healthInterests,
            healthConcerns: healthConcerns,
            email: email,
            dailyReminder: dailyReminder
        )
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
        patientID = question.patientID
        promptText = question.promptText
        text = question.text
    }

    func update(from question: Question) {
        patientID = question.patientID
        promptText = question.promptText
        text = question.text
    }

    var domainModel: Question {
        Question(
            id: id,
            patientID: patientID,
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
    var summaryLong: String
    var transcriptPath: String

    init(entry: DiaryEntry) {
        id = entry.id
        patientID = entry.patientID
        day = entry.day
        questions = entry.questions
        promptText = entry.promptText
        summaryShort = entry.summaryShort
        summaryLong = entry.summaryLong
        transcriptPath = entry.transcriptPath
    }

    func update(from entry: DiaryEntry) {
        patientID = entry.patientID
        day = entry.day
        questions = entry.questions
        promptText = entry.promptText
        summaryShort = entry.summaryShort
        summaryLong = entry.summaryLong
        transcriptPath = entry.transcriptPath
    }

    var domainModel: DiaryEntry {
        DiaryEntry(
            id: id,
            patientID: patientID,
            day: day,
            questions: questions,
            promptText: promptText,
            summaryShort: summaryShort,
            summaryLong: summaryLong,
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
