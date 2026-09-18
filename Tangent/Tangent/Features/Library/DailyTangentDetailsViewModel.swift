import Combine
import Foundation

@MainActor
final class DailyTangentDetailsViewModel: ObservableObject {
    private enum SummaryState: Equatable {
        /// Nothing decided yet: still loading, or transcribing, or about to
        /// start. The screen says nothing rather than claiming there is no
        /// summary a moment before writing one.
        case pending
        case generating
        case settled
        /// `needsModel` means no weights are on disk, so the fix is in Settings
        /// rather than another attempt.
        case failed(message: String, needsModel: Bool)
    }

    /// What the summary section should show. One value, so the view never has
    /// to reconcile a state with a half-arrived stream and flicker between them.
    enum SummaryDisplay: Equatable {
        case nothingYet
        case writing(String)
        case written(String)
        case failed(message: String, needsModel: Bool)
        case never
    }

    @Published private(set) var entry: DiaryEntry?
    @Published private(set) var transcript: String?
    @Published private(set) var isTranscribing = false
    // Read through `summaryDisplay`; the raw state is the view model's own.
    @Published private var summaryState: SummaryState = .pending
    /// The short summary as the model writes it, until the saved entry takes
    /// over.
    @Published private var streamingShortSummary: StreamedText?
    @Published private(set) var loadError: String?

    private let noteStore: any NoteStore
    private let transcriber: (any Transcriber)?
    private let summaryGenerator: (any SummaryGenerator)?
    private let diaryID: UUID
    let streamsTranscript: Bool

    init(
        noteStore: any NoteStore,
        transcriber: (any Transcriber)? = nil,
        summaryGenerator: (any SummaryGenerator)? = nil,
        diaryID: UUID,
        streamsTranscript: Bool = false
    ) {
        self.noteStore = noteStore
        self.transcriber = transcriber
        self.summaryGenerator = summaryGenerator
        self.diaryID = diaryID
        self.streamsTranscript = streamsTranscript
    }

    var isGenerating: Bool {
        if case .generating = summaryState { return true }
        return false
    }

    var summaryDisplay: SummaryDisplay {
        switch summaryState {
        case .pending:
            return .nothingYet

        case .failed(let message, let needsModel):
            return .failed(message: message, needsModel: needsModel)

        case .generating:
            guard let streaming = streamingShortSummary else { return .nothingYet }
            // The model closes the short summary long before it finishes the
            // long one. Once it has, this is finished text, not a work in
            // progress, and saying otherwise is what made it look stuck.
            return streaming.isComplete
                ? .written(streaming.text)
                : .writing(streaming.text)

        case .settled:
            let saved = entry?.summaryShort ?? ""
            return saved.isEmpty ? .never : .written(saved)
        }
    }

    /// The long summary is written and stored for insights, but the day's
    /// screen shows only the short one.
    var hasSummary: Bool {
        guard let entry else { return false }
        return !entry.summaryShort.isEmpty
    }

    func start() async {
        await load()
        if transcript == nil, streamsTranscript || hasPendingAudio {
            await transcribeFreshRecording(animate: streamsTranscript)
        }
        await generateSummaryIfNeeded()
        if case .pending = summaryState { summaryState = .settled }
    }

    func load() async {
        do {
            entry = try await noteStore.diaryEntry(id: diaryID)
            transcript = Self.storedTranscript(from: entry)
            loadError = entry == nil ? "This Tangent could not be found." : nil
        } catch {
            loadError = "This Tangent could not be loaded."
        }
    }

    /// Runs the model again for an entry that failed, or was recorded before a
    /// model was available.
    func regenerate() async {
        await generateSummary()
    }

    nonisolated static func loadTranscript(at path: String) -> String? {
        guard !path.isEmpty,
              path.lowercased().hasSuffix(".txt"),
              let text = try? String(
                  contentsOfFile: path,
                  encoding: .utf8
              ) else {
            return nil
        }
        let transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return transcript.isEmpty ? nil : transcript
    }

    private static func storedTranscript(from entry: DiaryEntry?) -> String? {
        guard let entry else { return nil }
        return loadTranscript(at: entry.transcriptPath)
    }

    private var hasPendingAudio: Bool {
        let path = entry?.transcriptPath.lowercased() ?? ""
        return path.hasSuffix(".m4a") || path.hasSuffix(".caf") || path.hasSuffix(".wav")
    }

    private func transcribeFreshRecording(animate: Bool) async {
        guard let transcriber,
              let path = entry?.transcriptPath,
              !path.isEmpty
        else {
            return
        }

        isTranscribing = true
        do {
            let fullText = try await transcriber.transcribe(
                audioAt: URL(fileURLWithPath: path)
            )
            if animate {
                await reveal(fullText)
            } else {
                transcript = fullText
            }
            try await persist(fullText)
        } catch {
            if transcript == nil {
                loadError = error.localizedDescription
            }
        }
        isTranscribing = false
    }

    private func reveal(_ fullText: String) async {
        var current = ""
        for character in fullText {
            current.append(character)
            if character.isWhitespace || current.count.isMultiple(of: 3) {
                transcript = current
                try? await Task.sleep(for: .milliseconds(12))
            }
        }
        transcript = fullText
    }

    /// Stores the transcript and points the entry at it. The summaries stay
    /// empty until the model has written them.
    private func persist(_ transcript: String) async throws {
        guard var entry else { return }
        let audioPath = entry.transcriptPath
        let storedPath = try RecordHomeViewModel.writeTranscript(transcript)
        entry.transcriptPath = storedPath
        try await noteStore.saveDiaryEntry(entry)
        self.entry = entry
        if audioPath != storedPath {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: audioPath)
            )
        }
    }

    private func generateSummaryIfNeeded() async {
        guard !hasSummary, !isGenerating else { return }
        await generateSummary()
    }

    private func generateSummary() async {
        guard let summaryGenerator,
              let entry,
              let transcript,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        let profile: PatientProfile?
        do {
            profile = try await noteStore.patientProfiles().first
        } catch {
            summaryState = .failed(message: error.localizedDescription, needsModel: false)
            return
        }
        guard let profile else {
            summaryState = .failed(
                message: "Your profile is needed to write a summary.",
                needsModel: false
            )
            return
        }

        streamingShortSummary = nil
        summaryState = .generating
        do {
            let generated = try await summaryGenerator.generateSummary(
                transcript: transcript,
                profile: profile,
                template: .dailySummary,
                onShortSummary: { [weak self] partial in
                    Task { @MainActor in
                        guard let self, self.isGenerating else { return }
                        self.streamingShortSummary = partial
                    }
                }
            )

            var updated = entry
            updated.summaryShort = generated.short
            updated.summaryLong = generated.long
            updated.promptText = generated.promptText
            try await noteStore.saveDiaryEntry(updated)
            self.entry = updated
            streamingShortSummary = nil
            summaryState = .settled
        } catch {
            summaryState = .failed(
                message: error.localizedDescription,
                needsModel: Self.needsModel(error)
            )
        }
    }

    private static func needsModel(_ error: Error) -> Bool {
        guard let error = error as? SummaryGenerationError else { return false }
        if case .modelNotDownloaded = error { return true }
        return false
    }
}
