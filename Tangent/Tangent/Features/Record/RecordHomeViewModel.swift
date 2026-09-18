import Foundation

@MainActor
final class RecordHomeViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case failed(message: String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var currentPromptQuestion: String?
    @Published private(set) var promptedQuestions: [DiaryQuestion] = []

    private let audioRecorder: any AudioRecorder
    private let transcriber: any Transcriber
    private let noteStore: any NoteStore
    private var elapsedTask: Task<Void, Never>?
    private var questionTask: Task<Void, Never>?
    private var isFinishing = false
    private let initialQuestionDelay: Duration
    private let questionInterval: Duration

    init(
        audioRecorder: any AudioRecorder,
        transcriber: any Transcriber,
        noteStore: any NoteStore,
        initialQuestionDelay: Duration = .seconds(3),
        questionInterval: Duration = .seconds(10)
    ) {
        self.audioRecorder = audioRecorder
        self.transcriber = transcriber
        self.noteStore = noteStore
        self.initialQuestionDelay = initialQuestionDelay
        self.questionInterval = questionInterval
    }

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool { isRecording || isFinishing }

    var formattedElapsed: String {
        let total = max(0, Int(elapsed))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func startRecording() async {
        guard !isBusy else { return }
        switch phase {
        case .idle, .failed:
            break
        case .recording:
            return
        }

        do {
            try await audioRecorder.startRecording(to: Self.newRecordingDestination())
            elapsed = 0
            promptedQuestions = []
            currentPromptQuestion = nil
            phase = .recording
            startElapsedTimer()
            await startQuestionStream()
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    /// Stops the recording, saves today's diary entry, and returns its id.
    /// The record screen returns to idle immediately so no transcribing UI is shown.
    func stopRecording() async -> UUID? {
        guard phase == .recording, !isFinishing else { return nil }
        isFinishing = true
        stopElapsedTimer()
        stopQuestionStream()
        phase = .idle
        defer { isFinishing = false }

        do {
            let recordingURL = try await audioRecorder.stopRecording()
            return try await saveTodayEntry(
                transcript: "",
                transcriptPath: recordingURL.path,
                questions: promptedQuestions
            )
        } catch {
            phase = .failed(message: error.localizedDescription)
            return nil
        }
    }

    deinit {
        elapsedTask?.cancel()
        questionTask?.cancel()
    }

    private func saveTodayEntry(
        transcript: String,
        transcriptPath: String,
        questions: [DiaryQuestion]
    ) async throws -> UUID {
        guard let patient = try await noteStore.patientProfiles().first else {
            throw RecordPersistenceError.missingProfile
        }

        let summary = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "…"
            : Self.summarize(transcript)
        let entry = DiaryEntry(
            patientID: patient.id,
            day: Date(),
            questions: questions,
            promptText: "Daily Tangent recorded and transcribed on device",
            summaryShort: summary,
            summaryLong: transcript,
            transcriptPath: transcriptPath
        )
        try await noteStore.saveDiaryEntry(entry)
        return entry.id
    }

    nonisolated static func writeTranscript(
        _ transcript: String,
        directory: URL = URL.documentsDirectory
            .appending(path: "Transcripts", directoryHint: .isDirectory)
    ) throws -> String {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appending(path: "tangent-\(UUID().uuidString).txt")
        try transcript.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    nonisolated static func summarize(_ transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Today’s Tangent" }

        if let end = trimmed.firstIndex(where: { $0 == "." || $0 == "?" || $0 == "!" }) {
            return String(trimmed[...end]).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.count <= 120 { return trimmed }
        return String(trimmed.prefix(117)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func startElapsedTimer() {
        elapsedTask?.cancel()
        let startedAt = Date()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTask?.cancel()
        elapsedTask = nil
    }

    private func startQuestionStream() async {
        guard let patientID = try? await noteStore.patientProfiles().first?.id,
              let questions = try? await noteStore.questions(patientID: patientID),
              !questions.isEmpty,
              isRecording
        else {
            return
        }

        let shuffledQuestions = questions.shuffled()
        questionTask?.cancel()
        questionTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: initialQuestionDelay)

            for question in shuffledQuestions {
                guard !Task.isCancelled, isRecording else { return }
                currentPromptQuestion = question.text
                promptedQuestions.append(
                    DiaryQuestion(id: question.id, text: question.text)
                )
                try? await Task.sleep(for: questionInterval)
            }
        }
    }

    private func stopQuestionStream() {
        questionTask?.cancel()
        questionTask = nil
        currentPromptQuestion = nil
    }

    private static func newRecordingDestination() -> URL {
        let documents = URL.documentsDirectory
        let timestamp = Date.now.formatted(
            .iso8601
                .year().month().day()
                .timeSeparator(.omitted)
                .dateTimeSeparator(.standard)
        )
        return documents
            .appending(path: "Recordings", directoryHint: .isDirectory)
            .appending(path: "tangent-\(timestamp).m4a")
    }
}

private enum RecordPersistenceError: LocalizedError {
    case missingProfile

    var errorDescription: String? {
        "Your profile is needed to save today’s Tangent."
    }
}
