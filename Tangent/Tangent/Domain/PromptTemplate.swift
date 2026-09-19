import Foundation

/// A reusable prompt template, mirroring the PROMPT table. Placeholders are
/// filled at generation time, and the filled result is what `prompt_text`
/// stores on the row that used it.
struct PromptTemplate: Equatable, Sendable {
    static let transcriptPlaceholder = "{transcript}"
    static let profilePlaceholder = "{user_profile}"
    static let periodPlaceholder = "{period}"
    static let dailySummariesPlaceholder = "{daily_summaries}"

    var text: String

    init(text: String) {
        self.text = text
    }

    func filled(transcript: String, profile: PatientProfile) -> String {
        text
            .replacingOccurrences(
                of: Self.transcriptPlaceholder,
                with: transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            .replacingOccurrences(
                of: Self.profilePlaceholder,
                with: profile.promptDescription
            )
    }

    func filled(period: String, summaries: [DiarySummary]) -> String {
        let lines = summaries.sorted { $0.day < $1.day }.map { summary in
            let day = summary.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            return "\(day): \(summary.text)"
        }
        return text
            .replacingOccurrences(of: Self.periodPlaceholder, with: period)
            .replacingOccurrences(
                of: Self.dailySummariesPlaceholder,
                with: lines.joined(separator: "\n")
            )
    }
}

extension PromptTemplate {
    /// The single sentence stored for each diary entry.
    static let dailyShortSummary = PromptTemplate(
        text: """
        You are a helpful medical assistant. You are summarising one entry in a private
        voice diary and providing a short summary.

        SHORT SUMMARY GUIDELINES:
        One sentence, written as if the user wrote it: first person, "I" and "my".
        Examples of the style only, taken from other people's diaries. Never take a
        symptom, an activity or any other detail from them:
        "I slept more deeply and woke up feeling refreshed."
        "A mild headache appeared after lunch but eased by evening."
        "My energy dipped in the afternoon, so I took a short walk."

        Use the profile below to judge what to foreground. Do not treat anything in it
        as something said in this entry.

        USER PROFILE: {user_profile}

        TRANSCRIPT: {transcript}
        """
    )

    /// Read across a chosen range on the insights screen.
    static let weeklyInsights = PromptTemplate(
        text: """
        You are helping someone look back over a week of their private health diary,
        so they can spot habits that matter for staying healthy. Below are notes from
        each day. Write at most 5 short insights for them, speaking to them as "you".

        Pick what matters most for staying well: sleep, movement, stress, drinking,
        eating habits, or a symptom that keeps coming back. Say what changed over the
        week or what stood out. Leave out anything minor. Do not count days.

        Write for someone who finds health information hard: short everyday words, one
        sentence each, calm and kind, never alarming.

        Only use what is in the notes. Never say why something happened, even if the
        notes guess at a reason, and never name an illness.

        NOTES ({period}):
        {daily_summaries}
        """
    )
}

extension PatientProfile {
    /// The profile as compact plain text for `{user_profile}`.
    ///
    /// Empty fields are left out rather than filled with a placeholder, so the
    /// model is never handed a value the patient did not give. The email
    /// address is deliberately withheld: it tells the model nothing useful
    /// about the patient's health.
    var promptDescription: String {
        var lines: [String] = []

        if !name.isEmpty {
            lines.append("Name: \(name)")
        }
        if let age {
            lines.append("Age: \(age)")
        }
        if let weight {
            lines.append("Weight: \(Self.format(weight)) kg")
        }
        if !gender.isEmpty {
            lines.append("Gender: \(gender)")
        }
        if !healthInterests.isEmpty {
            lines.append("Health interests: \(healthInterests.joined(separator: " "))")
        }
        if !healthConcerns.isEmpty {
            lines.append("Health concerns: \(healthConcerns.joined(separator: " "))")
        }

        return lines.isEmpty ? "No profile details were given." : lines.joined(separator: "\n")
    }

    private static func format(_ weight: Double) -> String {
        weight == weight.rounded()
            ? String(Int(weight))
            : String(format: "%.1f", weight)
    }
}
