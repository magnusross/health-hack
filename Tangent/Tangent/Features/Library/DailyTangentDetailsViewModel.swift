import Combine
import Foundation

@MainActor
final class DailyTangentDetailsViewModel: ObservableObject {
    @Published private(set) var entry: DiaryEntry?
    @Published private(set) var transcript: String?
    @Published private(set) var isTranscribing = false
    @Published private(set) var loadError: String?

    private let noteStore: any NoteStore
    private let transcriber: (any Transcriber)?
    private let healthModel: (any HealthLanguageModel)?
    private let diaryID: UUID
    let streamsTranscript: Bool

    init(
        noteStore: any NoteStore,
        transcriber: (any Transcriber)? = nil,
        healthModel: (any HealthLanguageModel)? = nil,
        diaryID: UUID,
        streamsTranscript: Bool = false
    ) {
        self.noteStore = noteStore
        self.transcriber = transcriber
        self.healthModel = healthModel
        self.diaryID = diaryID
        self.streamsTranscript = streamsTranscript
    }

    func start() async {
        await load()
        guard transcript == nil else { return }
        if streamsTranscript || hasPendingAudio {
            await transcribeFreshRecording(animate: streamsTranscript)
        }
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
        if let fileTranscript = loadTranscript(at: entry.transcriptPath) {
            return fileTranscript
        }
        let long = entry.summaryLong.trimmingCharacters(in: .whitespacesAndNewlines)
        return long.isEmpty ? nil : long
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

    private func persist(_ transcript: String) async throws {
        guard var entry else { return }
        let audioPath = entry.transcriptPath
        let storedPath = try RecordHomeViewModel.writeTranscript(transcript)
        entry.summaryShort = "…"
        entry.summaryLong = transcript
        entry.transcriptPath = storedPath
        try await noteStore.saveDiaryEntry(entry)
        self.entry = entry

        if audioPath != storedPath {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: audioPath)
            )
        }

        let summary: String
        if let healthModel {
            do {
                summary = try await healthModel.summarize(transcript: transcript)
            } catch {
                summary = RecordHomeViewModel.summarize(transcript)
            }
        } else {
            summary = RecordHomeViewModel.summarize(transcript)
        }

        entry.summaryShort = summary
        try await noteStore.saveDiaryEntry(entry)
        self.entry = entry
    }
}
