import Foundation
import SwiftUI
import SwiftData
import os

@MainActor
class TranscriptionServiceRegistry {
    private weak var modelProvider: (any WhisperModelProvider)?
    private let modelsDirectory: URL
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.syntaxlabtechnology.quill", category: "TranscriptionServiceRegistry")

    private(set) lazy var localTranscriptionService = WhisperTranscriptionService(
        modelsDirectory: modelsDirectory,
        modelProvider: modelProvider
    )
    private(set) lazy var cloudTranscriptionService = CloudTranscriptionService(modelContext: modelContext)
    private(set) lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
    private(set) lazy var fluidAudioTranscriptionService = FluidAudioTranscriptionService()

    init(modelProvider: any WhisperModelProvider, modelsDirectory: URL, modelContext: ModelContext) {
        self.modelProvider = modelProvider
        self.modelsDirectory = modelsDirectory
        self.modelContext = modelContext
    }

    func service(for provider: ModelProvider) -> TranscriptionService {
        switch provider {
        case .whisper:
            return localTranscriptionService
        case .fluidAudio:
            return fluidAudioTranscriptionService
        case .nativeApple:
            return nativeAppleTranscriptionService
        default:
            return cloudTranscriptionService
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext = .currentDefaults) async throws -> String {
        let service = service(for: model.provider)
        let requestContext = enrichedRequestContext(context, for: model)
        logger.debug("Transcribing with \(model.displayName, privacy: .public) using \(String(describing: type(of: service)), privacy: .public)")
        return try await service.transcribe(audioURL: audioURL, model: model, context: requestContext)
    }

    func applyLocalTextProcessing(to text: String) -> String {
        let replacementDescriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled }
        )
        let snippetDescriptor = FetchDescriptor<TextSnippet>(
            predicate: #Predicate { $0.isEnabled }
        )
        let replacements = (try? modelContext.fetch(replacementDescriptor)) ?? []
        let snippets = (try? modelContext.fetch(snippetDescriptor)) ?? []
        return LocalTextProcessor.apply(to: text, replacements: replacements, snippets: snippets)
    }

    /// Creates a streaming or file-based session for the resolved transcription configuration.
    func createSession(for configuration: TranscriptionRuntimeConfiguration, onPartialTranscript: ((String) -> Void)? = nil) -> TranscriptionSession {
        let model = configuration.model
        let context = enrichedRequestContext(configuration.requestContext, for: model)

        if shouldUseRealtimeTranscription(for: configuration) {
            let streamingService = StreamingTranscriptionService(
                modelContext: modelContext,
                fluidAudioService: model.provider == .fluidAudio ? fluidAudioTranscriptionService : nil,
                onPartialTranscript: onPartialTranscript
            )
            let fallback = service(for: model.provider)
            return StreamingTranscriptionSession(
                streamingService: streamingService,
                fallbackService: fallback,
                context: context
            )
        } else {
            return FileTranscriptionSession(
                service: service(for: model.provider),
                context: context
            )
        }
    }

    private func enrichedRequestContext(
        _ context: TranscriptionRequestContext,
        for model: any TranscriptionModel
    ) -> TranscriptionRequestContext {
        guard model.provider == .whisper else { return context }

        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\.word)])
        let vocabulary = (try? modelContext.fetch(descriptor)) ?? []
        let prompt = LocalTextProcessor.vocabularyPrompt(terms: vocabulary.map(\.word))
        guard !prompt.isEmpty else { return context }

        return TranscriptionRequestContext(
            language: context.language,
            prompt: context.prompt,
            localVocabularyPrompt: prompt
        )
    }

    /// Whether the resolved transcription configuration should use real-time transcription.
    func shouldUseRealtimeTranscription(for configuration: TranscriptionRuntimeConfiguration) -> Bool {
        configuration.isRealtimeEnabled
    }

    func cleanup() async {
        await fluidAudioTranscriptionService.cleanup()
    }
}
