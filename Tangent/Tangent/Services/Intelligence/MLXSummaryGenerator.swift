import Foundation
import HuggingFace
import OSLog
import MLX
import MLXHuggingFace
import MLXLMCommon
import Tokenizers

/// Writes diary summaries with a 4-bit model running on the device's GPU.
///
/// An actor so generation is serialised and never touches the main thread, and
/// so the loaded model has one owner.
actor MLXSummaryGenerator: SummaryGenerator {
    /// Read with: log stream --device --predicate 'subsystem == "Personal.Tangent"'
    private static let log = Logger(subsystem: "Personal.Tangent", category: "Summary")

    /// The one resident model. 0.8 GB and 2.5 GB together will get the app
    /// killed on iOS, so switching models drops the previous one.
    private var loaded: (model: SummaryModelID, container: ModelContainer)?
    /// The load in flight, if any. An actor suspends at every `await`, so
    /// without this a second caller arriving mid-load starts its own.
    private var loading: (model: SummaryModelID, task: Task<ModelContainer, Error>)?

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
            attempt: 1,
            onShortSummary: onShortSummary
        )
        if let parsed = SummaryJSON.parse(first) {
            return GeneratedSummary(
                short: parsed.short,
                long: parsed.long,
                promptText: prompt
            )
        }

        // The output did not parse, but the short summary may still have been
        // finished before the model ran out of room. That is the only part the
        // day's screen shows, so keep it rather than paying for a whole second
        // run on a model that takes a minute.
        if let short = SummaryJSON.partialValue(of: "short_summary", in: first),
           short.isComplete {
            Self.log.notice("salvaged the short summary from an unparseable reply")
            return GeneratedSummary(
                short: short.text,
                long: SummaryJSON.partialValue(of: "long_summary", in: first)?.text ?? "",
                promptText: prompt
            )
        }

        // One retry. A model that wandered off the format usually comes back
        // when asked more bluntly.
        let retry = prompt + "\n\n" + Self.formatReminder
        let second = try await complete(
            prompt: retry,
            in: container,
            attempt: 2,
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
        attempt: Int,
        onShortSummary: (@Sendable (StreamedText) -> Void)?
    ) async throws -> String {
        let log = Self.log
        let output = try await container.perform { (context: ModelContext) -> String in
            let input = try await context.processor.prepare(
                input: UserInput(prompt: prompt)
            )
            // Near-deterministic: this is a record of what the patient said,
            // not a piece of writing that benefits from variety.
            let parameters = GenerateParameters(maxTokens: 800, temperature: 0.2)

            var output = ""
            var reported: StreamedText?
            var info: GenerateCompletionInfo?
            for await generation in try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: context
            ) {
                if Task.isCancelled { break }
                if let completion = generation.info { info = completion }
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

            if let info {
                log.notice(
                    """
                    attempt \(attempt, privacy: .public): \
                    prompt \(info.promptTokenCount, privacy: .public) tokens at \
                    \(info.promptTokensPerSecond, format: .fixed(precision: 1)) t/s, \
                    generated \(info.generationTokenCount, privacy: .public) at \
                    \(info.tokensPerSecond, format: .fixed(precision: 1)) t/s, \
                    stopped on \(String(describing: info.stopReason), privacy: .public), \
                    \(info.promptTime + info.generateTime, format: .fixed(precision: 1))s total
                    """
                )
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

        // Join a load already running for this model rather than starting a
        // second one. Warming on the record screen and generating after
        // transcription are two callers, and loading a 4B model twice is 5 GB
        // resident, which iOS kills the app for.
        if let loading, loading.model == model {
            return try await loading.task.value
        }
        loading?.task.cancel()

        Memory.cacheLimit = 20 * 1024 * 1024
        loaded = nil

        let task = Task<ModelContainer, Error> {
            try await model.factory.loadContainer(
                from: #hubDownloader(ModelStorage.client()),
                using: #huggingFaceTokenizerLoader(),
                configuration: model.configuration
            )
        }
        loading = (model, task)
        defer { loading = nil }

        do {
            let started = Date()
            let container = try await task.value
            loaded = (model, container)
            Self.log.notice(
                "loaded \(model.displayName, privacy: .public) in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s"
            )
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
