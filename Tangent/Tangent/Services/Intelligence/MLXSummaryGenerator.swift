import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLMCommon
import Tokenizers

/// Writes diary summaries with a 4-bit model running on the device's GPU.
///
/// An actor so generation is serialised and never touches the main thread, and
/// so the loaded model has one owner.
actor MLXSummaryGenerator: SummaryGenerator {
    /// The one resident model. 0.8 GB and 2.5 GB together will get the app
    /// killed on iOS, so switching models drops the previous one.
    private var loaded: (model: SummaryModelID, container: ModelContainer)?

    /// Loads the selected model so a summary asked for moments later does not
    /// have to wait for weights to come off disk.
    func prepare() async {
        let model = SelectedModelStore.selected
        guard ModelStorage.isDownloaded(model) else { return }
        _ = try? await container(for: model)
    }

    func generateSummary(
        transcript: String,
        profile: PatientProfile,
        template: PromptTemplate,
        onShortSummary: (@Sendable (StreamedText) -> Void)?
    ) async throws -> GeneratedSummary {
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            throw SummaryGenerationError.emptyTranscript
        }

        let model = SelectedModelStore.selected
        guard ModelStorage.isDownloaded(model) else {
            throw SummaryGenerationError.modelNotDownloaded(model)
        }

        let container = try await container(for: model)
        let prompt = template.filled(transcript: transcript, profile: profile)

        let first = try await complete(
            prompt: prompt,
            in: container,
            onShortSummary: onShortSummary
        )
        if let parsed = SummaryJSON.parse(first) {
            return GeneratedSummary(
                short: parsed.short,
                long: parsed.long,
                promptText: prompt
            )
        }

        // One retry. A model that wandered off the format usually comes back
        // when asked more bluntly.
        let retry = prompt + "\n\n" + Self.formatReminder
        let second = try await complete(
            prompt: retry,
            in: container,
            onShortSummary: onShortSummary
        )
        guard let parsed = SummaryJSON.parse(second) else {
            throw SummaryGenerationError.outputNotParseable
        }

        return GeneratedSummary(
            short: parsed.short,
            long: parsed.long,
            promptText: retry
        )
    }

    private func complete(
        prompt: String,
        in container: ModelContainer,
        onShortSummary: (@Sendable (StreamedText) -> Void)?
    ) async throws -> String {
        let output = try await container.perform { (context: ModelContext) -> String in
            let input = try await context.processor.prepare(
                input: UserInput(prompt: prompt)
            )
            // Near-deterministic: this is a record of what the patient said,
            // not a piece of writing that benefits from variety.
            let parameters = GenerateParameters(maxTokens: 800, temperature: 0.2)

            var output = ""
            var reported: StreamedText?
            for await generation in try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: context
            ) {
                if Task.isCancelled { break }
                guard let chunk = generation.chunk else { continue }
                output += chunk

                // The model writes short_summary first, so it can be shown
                // filling in while the long one is still being generated.
                guard let onShortSummary else { continue }
                let partial = SummaryJSON.partialValue(
                    of: "short_summary",
                    in: output
                )
                if let partial, partial != reported {
                    reported = partial
                    onShortSummary(partial)
                }
            }
            return output
        }

        try Task.checkCancellation()
        return output
    }

    private func container(for model: SummaryModelID) async throws -> ModelContainer {
        if let loaded, loaded.model == model {
            return loaded.container
        }

        Memory.cacheLimit = 20 * 1024 * 1024
        loaded = nil

        do {
            let container = try await model.factory.loadContainer(
                from: #hubDownloader(ModelStorage.client()),
                using: #huggingFaceTokenizerLoader(),
                configuration: model.configuration
            )
            loaded = (model, container)
            return container
        } catch {
            throw SummaryGenerationError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Dropped in only after the first attempt came back unparseable.
    private static let formatReminder = """
        Your last answer was not valid JSON. Answer again with the JSON object \
        only — no explanation, no code fence, nothing before or after it:
        {"short_summary": "...", "long_summary": "..."}
        """
}
