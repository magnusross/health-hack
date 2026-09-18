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
    /// The notes generation that is queued or running, if any.
    private var longWork: Task<GeneratedText, Error>?

    /// Loads the selected model so a summary asked for moments later does not
    /// have to wait for weights to come off disk.
    func prepare() async {
        let model = SelectedModelStore.selected
        guard ModelStorage.isDownloaded(model) else { return }
        _ = try? await container(for: model)
    }

    func generateShortSummary(
        transcript: String,
        profile: PatientProfile,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        // The sentence is the only thing anyone is waiting for. Notes still
        // running from an earlier entry are dropped rather than made to finish
        // first — the model runs one job at a time, so a queued paragraph the
        // user cannot see would sit in front of the sentence they can.
        longWork?.cancel()
        longWork = nil

        return try await generate(
            using: .dailyShortSummary,
            transcript: transcript,
            profile: profile,
            maxTokens: 120,
            label: "short",
            onPartial: onPartial
        )
    }

    func generateLongSummary(
        transcript: String,
        profile: PatientProfile
    ) async throws -> GeneratedText {
        longWork?.cancel()

        let work = Task { () throws -> GeneratedText in
            try await self.generate(
                using: .dailyLongSummary,
                transcript: transcript,
                profile: profile,
                maxTokens: 500,
                label: "long",
                onPartial: nil
            )
        }
        longWork = work
        defer { if longWork == work { longWork = nil } }

        return try await work.value
    }

    private func generate(
        using template: PromptTemplate,
        transcript: String,
        profile: PatientProfile,
        maxTokens: Int,
        label: String,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
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

        let raw = try await complete(
            prompt: prompt,
            in: container,
            maxTokens: maxTokens,
            label: label,
            onPartial: onPartial
        )

        try Task.checkCancellation()

        let text = SummaryText.clean(raw)
        guard !text.isEmpty else {
            throw SummaryGenerationError.unusableOutput
        }

        return GeneratedText(text: text, promptText: prompt)
    }

    private func complete(
        prompt: String,
        in container: ModelContainer,
        maxTokens: Int,
        label: String,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let log = Self.log
        let output = try await container.perform { (context: ModelContext) -> String in
            let input = try await context.processor.prepare(
                input: UserInput(prompt: prompt)
            )
            // Near-deterministic: this is a record of what the patient said,
            // not a piece of writing that benefits from variety.
            let parameters = GenerateParameters(
                maxTokens: maxTokens,
                temperature: 0.2
            )

            var output = ""
            var reported = ""
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

                // Every token is part of the summary now, so it goes straight
                // to the screen — no structure to wait for.
                guard let onPartial else { continue }
                let partial = SummaryText.clean(output)
                if partial != reported {
                    reported = partial
                    onPartial(partial)
                }
            }

            if let info {
                log.notice(
                    """
                    \(label, privacy: .public): prompt \(info.promptTokenCount, privacy: .public) tokens at \
                    \(info.promptTokensPerSecond, format: .fixed(precision: 1)) t/s, \
                    generated \(info.generationTokenCount, privacy: .public) at \
                    \(info.tokensPerSecond, format: .fixed(precision: 1)) t/s, \
                    stopped on \(String(describing: info.stopReason), privacy: .public), \
                    \(info.promptTime + info.generateTime, format: .fixed(precision: 1))s
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
}
