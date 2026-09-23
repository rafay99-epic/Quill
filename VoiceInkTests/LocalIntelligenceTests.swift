import Foundation
import Testing
@testable import VoiceInk

@Suite(.serialized)
struct LocalIntelligenceTests {
    @Test func vocabularyPromptIsDeterministicAndCapped() {
        let terms = (0..<60).map { "Term\($0)" }

        let prompt = LocalTextProcessor.vocabularyPrompt(terms: terms)

        #expect(prompt == LocalTextProcessor.vocabularyPrompt(terms: Array(terms.reversed())))
        #expect(prompt.utf8.count <= 512)
        #expect(prompt.split(separator: ",").count <= 50)
    }

    @Test func vocabularyPromptNormalizesAndDeduplicatesTerms() {
        let prompt = LocalTextProcessor.vocabularyPrompt(terms: ["  Quill\tEngine  ", "quill engine", "", "Syntlab"])

        #expect(prompt == "Vocabulary: Quill Engine, Syntlab")
    }

    @Test func localRulesApplyLongestFirstAndKeepDollarTextLiteral() {
        let replacements = [
            WordReplacement(originalText: "voice ink", replacementText: "Quill"),
            WordReplacement(originalText: "send", replacementText: "$1")
        ]
        let snippets = [
            TextSnippet(trigger: "insert address", expansion: "123 Main St")
        ]

        let result = LocalTextProcessor.apply(
            to: "Send this to Voice Ink. Insert address.",
            replacements: replacements,
            snippets: snippets
        )

        #expect(result == "$1 this to Quill. 123 Main St.", "Actual: \(result)")
    }

    @Test func localRulesRespectUnicodeWordBoundaries() {
        let replacement = WordReplacement(originalText: "مرحبا", replacementText: "hello")

        let result = LocalTextProcessor.apply(
            to: "مرحبا and xمرحباy",
            replacements: [replacement],
            snippets: []
        )

        #expect(result == "hello and xمرحباy")
    }

    @Test func preferredTextUsesCorrectionThenUsableEnhancement() {
        let transcription = Transcription(text: "Original", duration: 1, enhancedText: "Enhanced")
        #expect(transcription.preferredText == "Enhanced")

        transcription.correctedText = "Corrected"
        #expect(transcription.preferredText == "Corrected")

        transcription.correctedText = "   "
        transcription.enhancedText = "Enhancement failed: offline"
        #expect(transcription.preferredText == "Original")
    }

    @Test func csvKeepsCorrectedTranscriptAsSeparateColumn() {
        let transcription = Transcription(text: "Original", duration: 1, enhancedText: "Enhanced", correctedText: "Corrected")

        let csv = VoiceInkCSVExportService().generateCSV(for: [transcription])

        #expect(csv.hasPrefix("Original Transcript,Enhanced Transcript"))
        #expect(csv.contains(",Corrected Transcript\n"))
        #expect(csv.contains("Corrected"))
    }
}
