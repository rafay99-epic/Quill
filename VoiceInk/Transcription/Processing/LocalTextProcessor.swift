import Foundation

enum LocalTextProcessor {
    private struct Rule {
        let trigger: String
        let replacement: String
    }

    private static let vocabularyPrefix = "Vocabulary: "
    private static let vocabularyTermLimit = 50
    private static let vocabularyByteLimit = 512

    static func vocabularyPrompt(terms: [String]) -> String {
        var seen = Set<String>()
        var uniqueTerms: [String] = []

        for term in terms {
            let normalized = term
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            guard !normalized.isEmpty else { continue }

            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { continue }
            uniqueTerms.append(normalized)
        }

        let sortedTerms = uniqueTerms.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        guard !sortedTerms.isEmpty else { return "" }

        var prompt = vocabularyPrefix
        for term in sortedTerms.prefix(vocabularyTermLimit) {
            let candidate = prompt == vocabularyPrefix ? prompt + term : "\(prompt), \(term)"
            guard candidate.utf8.count <= vocabularyByteLimit else { continue }
            prompt = candidate
        }

        return prompt == vocabularyPrefix ? "" : prompt
    }

    static func apply(
        to text: String,
        replacements: [WordReplacement],
        snippets: [TextSnippet]
    ) -> String {
        let replacementRules = replacements.compactMap { replacement -> [Rule]? in
            guard replacement.isEnabled else { return nil }
            let rules = replacement.originalText
                .split(separator: ",")
                .map { Rule(trigger: $0.trimmingCharacters(in: .whitespacesAndNewlines), replacement: replacement.replacementText) }
                .filter { !$0.trigger.isEmpty }
            return rules.isEmpty ? nil : rules
        }.flatMap { $0 }

        let snippetRules = snippets.compactMap { snippet -> Rule? in
            let trigger = snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            guard snippet.isEnabled, !trigger.isEmpty else { return nil }
            return Rule(trigger: trigger, replacement: snippet.expansion)
        }

        var result = text
        for rule in replacementRules.sorted(by: areRulesOrderedBefore) {
            result = apply(rule: rule, to: result)
        }
        for rule in snippetRules.sorted(by: areRulesOrderedBefore) {
            result = apply(rule: rule, to: result)
        }
        return result
    }

    private static func areRulesOrderedBefore(_ lhs: Rule, _ rhs: Rule) -> Bool {
        if lhs.trigger.utf16.count != rhs.trigger.utf16.count {
            return lhs.trigger.utf16.count > rhs.trigger.utf16.count
        }
        if lhs.trigger != rhs.trigger {
            return lhs.trigger < rhs.trigger
        }
        return lhs.replacement < rhs.replacement
    }

    private static func apply(rule: Rule, to text: String) -> String {
        guard usesWordBoundaries(for: rule.trigger) else {
            return text.replacingOccurrences(
                of: rule.trigger,
                with: rule.replacement,
                options: .caseInsensitive
            )
        }

        let escapedTrigger = NSRegularExpression.escapedPattern(for: rule.trigger)
        let pattern = "(?<![\\p{L}\\p{N}\\p{M}])\(escapedTrigger)(?![\\p{L}\\p{N}\\p{M}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }

        let source = text as NSString
        let result = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        for match in matches.reversed() {
            result.replaceCharacters(in: match.range, with: rule.replacement)
        }
        return result as String
    }

    private static func usesWordBoundaries(for text: String) -> Bool {
        let nonSpacedScripts: [ClosedRange<UInt32>] = [
            0x3040...0x309F,
            0x30A0...0x30FF,
            0x3400...0x4DBF,
            0x4E00...0x9FFF,
            0xF900...0xFAFF,
            0x20000...0x2A6DF,
            0x2A700...0x2B73F,
            0x2B740...0x2B81F,
            0x2B820...0x2CEAF,
            0xAC00...0xD7AF,
            0x0E00...0x0E7F
        ]

        return !text.unicodeScalars.contains { scalar in
            nonSpacedScripts.contains { $0.contains(scalar.value) }
        }
    }
}
