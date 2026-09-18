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

    private let audioRecorder: any AudioRecorder
    private let transcriber: any Transcriber
    private let noteStore: any NoteStore
    private var elapsedTask: Task<Void, Never>?
    private var isFinishing = false

    init(
        audioRecorder: any AudioRecorder,
        transcriber: any Transcriber,
        noteStore: any NoteStore
    ) {
        self.audioRecorder = audioRecorder
        self.transcriber = transcriber
        self.noteStore = noteStore
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
            phase = .recording
            startElapsedTimer()
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
        phase = .idle
        defer { isFinishing = false }

        do {
            let recordingURL = try await audioRecorder.stopRecording()
            return try await saveTodayEntry(transcriptPath: recordingURL.path)
        } catch {
            phase = .failed(message: error.localizedDescription)
            return nil
        }
    }

    deinit {
        elapsedTask?.cancel()
    }

    /// Saves the entry with the audio path only. The transcript and both
    /// summaries are filled in on the daily details screen.
    private func saveTodayEntry(transcriptPath: String) async throws -> UUID {
        guard let patient = try await noteStore.patientProfiles().first else {
            throw RecordPersistenceError.missingProfile
        }

        let entry = DiaryEntry(
            patientID: patient.id,
            day: Date(),
            questions: [DiaryQuestion(text: "How have you been feeling?")],
            promptText: "Daily Tangent recorded and transcribed on device",
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
