import Foundation
#if !TANGENT_LEGACY_MLX
import HuggingFace
import MLXHuggingFace
#endif
import OSLog
import MLX
import MLXLMCommon
import Tokenizers

/// Writes diary summaries with a 4-bit model running on the device's GPU.
///
/// An actor so generation is serialised and never touches the main thread, and
/// so the loaded model has one owner.
actor MLXDiaryLanguageModel: DiaryLanguageModel {
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

    func generateShortSummary(
        transcript: String,
        profile: UserProfile,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        return try await generate(
            using: .dailyShortSummary,
            transcript: transcript,
            profile: profile,
            maxTokens: 120,
            label: "short",
            onPartial: onPartial
        )
    }

    /// Generates insights using saved short summaries only.
    func generateInsights(
        from summaries: [DiarySummary],
        focus: DiaryFocus,
        period: String,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        guard !summaries.isEmpty else {
            throw DiaryLanguageModelError.notEnoughEntries
        }

        let model = SelectedModelStore.selected
        guard ModelStorage.isDownloaded(model) else {
            throw DiaryLanguageModelError.modelNotDownloaded(model)
        }

        let container = try await container(for: model)
        let prompt = PromptTemplate.weeklyInsights.filled(
            period: period,
            summaries: summaries,
            focus: focus
        )

        let raw = try await complete(
            prompt: prompt,
            in: container,
            model: model,
            maxTokens: 400,
            label: "insights · \(model.displayName)",
            onPartial: onPartial
        )

        try Task.checkCancellation()

        let text = SummaryText.clean(raw)
        guard !text.isEmpty else {
            throw DiaryLanguageModelError.unusableOutput
        }

        return GeneratedText(text: text, promptText: prompt)
    }

    private func generate(
        using template: PromptTemplate,
        transcript: String,
        profile: UserProfile,
        maxTokens: Int,
        label: String,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            throw DiaryLanguageModelError.emptyTranscript
        }

        let model = SelectedModelStore.selected
        guard ModelStorage.isDownloaded(model) else {
            throw DiaryLanguageModelError.modelNotDownloaded(model)
        }

        let container = try await container(for: model)
        let prompt = template.filled(transcript: transcript, profile: profile)

        let raw = try await complete(
            prompt: prompt,
            in: container,
            model: model,
            maxTokens: maxTokens,
            label: "\(label) · \(model.displayName)",
            onPartial: onPartial
        )

        try Task.checkCancellation()

        let text = SummaryText.clean(raw)
        guard !text.isEmpty else {
            throw DiaryLanguageModelError.unusableOutput
        }

        return GeneratedText(text: text, promptText: prompt)
    }

    private func complete(
        prompt: String,
        in container: ModelContainer,
        model: SummaryModelID,
        maxTokens: Int,
        label: String,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> String {
        try Task.checkCancellation()
        // Near-deterministic: this is a record of what the user said, not a
        // piece of writing that benefits from variety.
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.2)

        // container.generate holds the model exclusively for the prefill and
        // releases it to decode. Consuming the stream inside container.perform
        // instead would hold it for the whole run, which is how one summary
        // came to block every other.
        #if TANGENT_LEGACY_MLX
        let stream = try await container.perform { context in
            let input = try await context.processor.prepare(input: UserInput(
                prompt: prompt,
                additionalContext: model.disablesThinking ? ["enable_thinking": false] : nil
            ))
            try Task.checkCancellation()
            return try MLXLMCommon.generate(input: input, parameters: parameters, context: context)
        }
        #else
        let input = try await container.prepare(input: UserInput(
            prompt: prompt,
            additionalContext: model.disablesThinking ? ["enable_thinking": false] : nil
        ))
        try Task.checkCancellation()
        let stream = try await container.generate(input: input, parameters: parameters)
        #endif

        var output = ""
        var reported = ""
        var info: GenerateCompletionInfo?
        for await generation in stream {
            if Task.isCancelled { break }
            if let completion = generation.info { info = completion }
            guard let chunk = generation.chunk else { continue }
            output += chunk

            // Every token is part of the summary now, so it goes straight to
            // the screen — no structure to wait for.
            guard let onPartial else { continue }
            let partial = SummaryText.clean(output)
            if partial != reported {
                reported = partial
                onPartial(partial)
            }
        }

        if let info {
            #if TANGENT_LEGACY_MLX
            let stopReason = "unavailable in MLX 2.x"
            #else
            let stopReason = String(describing: info.stopReason)
            #endif
            Self.log.notice(
                """
                \(label, privacy: .public): prompt \(info.promptTokenCount, privacy: .public) tokens at \
                \(info.promptTokensPerSecond, format: .fixed(precision: 1)) t/s, \
                generated \(info.generationTokenCount, privacy: .public) at \
                \(info.tokensPerSecond, format: .fixed(precision: 1)) t/s, \
                stopped on \(stopReason, privacy: .public), \
                \(info.promptTime + info.generateTime, format: .fixed(precision: 1))s
                """
            )
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

        #if TANGENT_LEGACY_MLX
        GPU.set(cacheLimit: 20 * 1024 * 1024)
        #else
        Memory.cacheLimit = 20 * 1024 * 1024
        #endif
        loaded = nil

        let task = Task<ModelContainer, Error> {
            #if TANGENT_LEGACY_MLX
            // Loading from the completed local snapshot keeps generation offline.
            try await model.factory.loadContainer(
                hub: ModelStorage.client(),
                configuration: ModelConfiguration(
                    directory: ModelStorage.modelDirectory(model),
                    extraEOSTokens: model.configuration.extraEOSTokens
                )
            )
            #else
            try await model.factory.loadContainer(
                from: #hubDownloader(ModelStorage.client()),
                using: #huggingFaceTokenizerLoader(),
                configuration: model.configuration
            )
            #endif
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
            throw DiaryLanguageModelError.modelLoadFailed(error.localizedDescription)
        }
    }
}
