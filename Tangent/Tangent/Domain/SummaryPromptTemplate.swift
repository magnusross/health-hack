import Foundation

/// A reusable prompt template, mirroring the PROMPT table. `{transcript}` and
/// `{user_profile}` are filled at generation time, and the filled result is
/// what `DIARY.prompt_text` stores.
struct SummaryPromptTemplate: Equatable, Sendable {
    static let transcriptPlaceholder = "{transcript}"
    static let profilePlaceholder = "{user_profile}"

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
}

extension SummaryPromptTemplate {
    static let dailySummary = SummaryPromptTemplate(
        text: """
        You are a helpful medical assistant. You are helping me summarise an entry in my private voice diary. Based on my
        transcript and my profile, write two summaries. Write both as if I wrote them:
        first person, "I" and "my", throughout.

        1. short_summary — one sentence. Examples of the style only, taken from other people's diaries. Never take a
           symptom, an activity or any other detail from them:
           "I slept more deeply and woke up feeling refreshed."
           "A mild headache appeared after lunch but eased by evening."
           "My energy dipped in the afternoon, so I took a short walk."
           "I felt calmer today and had steady energy throughout the day."
        2. long_summary — one dense paragraph with the clinically useful detail: symptoms with their timing,
           duration and severity; what changed and in which direction; sleep, energy,
           appetite, pain, mood, movement; work, home and social context; anything new
           or different.

        Rules:
        - Record only what I said from the transcript below.
        - Do not add or infer. No advice, no diagnosis, no causes. "I slept badly and
          felt flat" is correct; "my low mood is caused by poor sleep" is not.
        - Neutral tone. Do not reassure, do not alarm.
        - Ignore filler and false starts; leave out anything unintelligible.
        - Plain language, no jargon, no markdown.

        Return only this JSON and nothing else:
        {"short_summary": "...", "long_summary": "..."}

        TRANSCRIPT: {transcript}

        Use my profile to judge what to foreground and how to pitch the language. Do not
        mention it, and do not treat anything in it as something I said in this entry.

        USER PROFILE: {user_profile}
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
            lines.append("Health interests: \(healthInterests.joined(separator: ", "))")
        }
        if !healthConcerns.isEmpty {
            lines.append("Health concerns: \(healthConcerns.joined(separator: ", "))")
        }

        return lines.isEmpty ? "No profile details were given." : lines.joined(separator: "\n")
    }

    private static func format(_ weight: Double) -> String {
        weight == weight.rounded()
            ? String(Int(weight))
            : String(format: "%.1f", weight)
    }
}
