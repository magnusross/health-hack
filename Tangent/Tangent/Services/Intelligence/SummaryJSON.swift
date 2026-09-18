import Foundation

/// Reads the model's completion back into two summaries.
///
/// The prompt asks for bare JSON, but a model will sometimes fence it, lead
/// with a sentence, or add one afterwards. Rather than trusting the whole
/// completion to be JSON, this pulls out every balanced object in it and takes
/// the first one that decodes.
enum SummaryJSON {
    private struct Payload: Decodable {
        let shortSummary: String
        let longSummary: String

        enum CodingKeys: String, CodingKey {
            case shortSummary = "short_summary"
            case longSummary = "long_summary"
        }
    }

    static func parse(_ output: String) -> (short: String, long: String)? {
        for candidate in objects(in: output) {
            guard let data = candidate.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data)
            else {
                continue
            }

            let short = payload.shortSummary
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let long = payload.longSummary
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !short.isEmpty, !long.isEmpty else { continue }

            return (short, long)
        }
        return nil
    }

    /// Every top-level `{...}` run in the text, in the order they appear.
    /// Braces inside string literals are ignored, so a summary that mentions
    /// one does not break the scan.
    static func objects(in text: String) -> [String] {
        var objects: [String] = []
        var depth = 0
        var start: String.Index?
        var insideString = false
        var escaped = false

        for index in text.indices {
            let character = text[index]

            if insideString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    insideString = false
                }
                continue
            }

            switch character {
            case "\"":
                insideString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}":
                guard depth > 0 else { break }
                depth -= 1
                if depth == 0, let start {
                    objects.append(String(text[start...index]))
                }
            default:
                break
            }
        }

        return objects
    }
}
