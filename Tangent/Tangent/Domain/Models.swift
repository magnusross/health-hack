import Foundation

struct PatientProfile: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var age: Int?
    var weight: Double?
    var gender: String
    var healthInterests: [String]
    var healthConcerns: [String]
    var email: String
    var dailyReminder: Date?

    init(
        id: UUID = UUID(),
        name: String,
        age: Int? = nil,
        weight: Double? = nil,
        gender: String = "",
        healthInterests: [String] = [],
        healthConcerns: [String] = [],
        email: String = "",
        dailyReminder: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.weight = weight
        self.gender = gender
        self.healthInterests = healthInterests
        self.healthConcerns = healthConcerns
        self.email = email
        self.dailyReminder = dailyReminder
    }
}

struct Prompt: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct Question: Identifiable, Equatable, Sendable {
    let id: UUID
    let patientID: UUID
    var promptText: String
    var text: String

    init(
        id: UUID = UUID(),
        patientID: UUID,
        promptText: String,
        text: String
    ) {
        self.id = id
        self.patientID = patientID
        self.promptText = promptText
        self.text = text
    }
}

struct DiaryQuestion: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct DiaryEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let patientID: UUID
    var day: Date
    var questions: [DiaryQuestion]
    var promptText: String
    var summaryShort: String
    var transcriptPath: String

    init(
        id: UUID = UUID(),
        patientID: UUID,
        day: Date,
        questions: [DiaryQuestion] = [],
        promptText: String,
        summaryShort: String = "",
        transcriptPath: String = ""
    ) {
        self.id = id
        self.patientID = patientID
        self.day = day
        self.questions = questions
        self.promptText = promptText
        self.summaryShort = summaryShort
        self.transcriptPath = transcriptPath
    }
}

/// The only diary content available to insight generation.
struct DiarySummary: Equatable, Sendable {
    let day: Date
    let text: String

    init?(entry: DiaryEntry) {
        let text = entry.summaryShort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        self.day = entry.day
        self.text = text
    }
}

struct Insight: Identifiable, Equatable, Sendable {
    let id: UUID
    var day: Date
    var generatedFrom: Date
    var generatedTo: Date
    var promptText: String
    var text: String

    init(
        id: UUID = UUID(),
        day: Date,
        generatedFrom: Date,
        generatedTo: Date,
        promptText: String,
        text: String
    ) {
        self.id = id
        self.day = day
        self.generatedFrom = generatedFrom
        self.generatedTo = generatedTo
        self.promptText = promptText
        self.text = text
    }
}
