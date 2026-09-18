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

    /// The value of a key in a JSON object that is still arriving.
    ///
    /// Used to show a summary being written rather than the raw JSON carrying
    /// it. Returns nil until the key's opening quote has appeared; after that
    /// it returns however much of the value has been generated so far, and
    /// whether the model has closed it.
    static func partialValue(of key: String, in text: String) -> StreamedText? {
        guard let keyRange = text.range(of: "\"\(key)\"") else { return nil }
        var index = keyRange.upperBound

        guard let colon = skipWhitespace(from: index, in: text),
              text[colon] == ":"
        else {
            return nil
        }
        index = text.index(after: colon)

        guard let quote = skipWhitespace(from: index, in: text),
              text[quote] == "\""
        else {
            return nil
        }
        index = text.index(after: quote)

        var raw = ""
        var escaped = false
        var isComplete = false
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                raw.append(character)
                escaped = false
            } else if character == "\\" {
                raw.append(character)
                escaped = true
            } else if character == "\"" {
                isComplete = true
                break
            } else {
                raw.append(character)
            }
            index = text.index(after: index)
        }

        return StreamedText(text: unescape(raw), isComplete: isComplete)
    }

    private static func skipWhitespace(
        from start: String.Index,
        in text: String
    ) -> String.Index? {
        var index = start
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        return index < text.endIndex ? index : nil
    }

    /// Decodes JSON string escapes by hand rather than through `JSONDecoder`,
    /// because the tail of a streaming value is routinely half an escape
    /// sequence, and a literal newline the model emitted would make the whole
    /// value undecodable. An unfinished escape is dropped; the next chunk
    /// brings it.
    private static func unescape(_ raw: String) -> String {
        let characters = Array(raw)
        var result = ""
        var index = 0

        while index < characters.count {
            let character = characters[index]
            guard character == "\\" else {
                result.append(character)
                index += 1
                continue
            }
            guard index + 1 < characters.count else { break }

            let escape = characters[index + 1]
            index += 2
            switch escape {
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "r": result.append("\r")
            case "b": result.append("\u{08}")
            case "f": result.append("\u{0C}")
            case "u":
                guard index + 4 <= characters.count else { return result }
                let hex = String(characters[index ..< index + 4])
                if let value = UInt32(hex, radix: 16),
                   let scalar = Unicode.Scalar(value) {
                    result.append(Character(scalar))
                }
                index += 4
            default:
                // Covers \" \\ and \/
                result.append(escape)
            }
        }

        return result
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
