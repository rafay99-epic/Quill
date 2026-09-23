import Foundation
import AVFoundation
import os

class WhisperTranscriptionService: TranscriptionService {

    private let logger = Logger(subsystem: "com.syntaxlabtechnology.quill", category: "WhisperTranscriptionService")
    private let modelsDirectory: URL
    private weak var modelProvider: (any WhisperModelProvider)?

    init(modelsDirectory: URL, modelProvider: (any WhisperModelProvider)? = nil) {
        self.modelsDirectory = modelsDirectory
        self.modelProvider = modelProvider
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws -> String {
        guard model.provider == .whisper else {
            throw VoiceInkEngineError.modelLoadFailed
        }

        logger.notice("Initiating local transcription for model: \(model.displayName, privacy: .public)")

        let whisperContext: WhisperContext
        let ownsContext: Bool

        if let provider = modelProvider,
           await provider.isModelLoaded,
           let loadedContext = await provider.whisperContext,
           await provider.loadedWhisperModel?.name == model.name {
            logger.notice("Using already loaded model: \(model.name, privacy: .public)")
            whisperContext = loadedContext
            ownsContext = false
        } else {
            let resolvedURL: URL? = await modelProvider?.availableModels.first(where: { $0.name == model.name })?.url
            guard let modelURL = resolvedURL, FileManager.default.fileExists(atPath: modelURL.path) else {
                logger.error("❌ Model file not found for: \(model.name, privacy: .public)")
                throw VoiceInkEngineError.modelLoadFailed
            }

            logger.notice("Loading model: \(model.name, privacy: .public)")
            do {
                whisperContext = try await WhisperContext.createContext(path: modelURL.path)
                ownsContext = true
            } catch {
                logger.error("❌ Failed to load model: \(model.name, privacy: .public) - \(error, privacy: .public)")
                throw VoiceInkEngineError.modelLoadFailed
            }
        }

        do {
            let data = try readAudioSamples(audioURL)
            let prompt = [context.prompt, context.localVocabularyPrompt]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let success = await whisperContext.fullTranscribe(
                samples: data,
                language: context.language,
                prompt: prompt
            )

            guard success else {
                logger.error("❌ Core transcription engine failed (whisper_full).")
                throw VoiceInkEngineError.whisperCoreFailed
            }

            let text = await whisperContext.getTranscription()
            if ownsContext {
                await whisperContext.releaseResources()
            }
            logger.notice("Whisper transcription completed successfully.")
            return text
        } catch {
            if ownsContext {
                await whisperContext.releaseResources()
            }
            throw error
        }
    }

    private func readAudioSamples(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let floats = stride(from: 44, to: data.count, by: 2).map {
            return data[$0..<$0 + 2].withUnsafeBytes {
                let short = Int16(littleEndian: $0.load(as: Int16.self))
                return max(-1.0, min(Float(short) / 32767.0, 1.0))
            }
        }
        return floats
    }
}
