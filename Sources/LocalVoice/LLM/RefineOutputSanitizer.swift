import Foundation

enum RefineOutputSanitizer {
    static func clean(_ output: String) -> String {
        var cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)

        while let unwrapped = unwrapQuoted(cleaned) {
            cleaned = unwrapped.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }

    private static func unwrapQuoted(_ text: String) -> String? {
        guard text.count >= 2,
              let first = text.first,
              let last = text.last,
              matchingQuote(for: first) == last
        else { return nil }

        return String(text.dropFirst().dropLast())
    }

    private static func matchingQuote(for quote: Character) -> Character? {
        switch quote {
        case "\"": return "\""
        case "“":  return "”"
        case "«":  return "»"
        default:   return nil
        }
    }
}
