import SwiftUI

/// The Record Tangent screen: a calm idle state with an animated orb that
/// starts a recording on tap, then shows a stop control and elapsed time.
/// Transcription is performed entirely on-device.
struct RecordHomeView: View {
    @StateObject private var model: RecordHomeViewModel

    private let openSettings: () -> Void
    private let onRecordingFinished: (UUID) -> Void

    /// Delay before "Tap to record" fades in. Overridable for previews.
    private let instructionDelay: TimeInterval
    /// Forces the Reduce Motion presentation in previews.
    private let forcesReducedMotion: Bool
    /// True while the Record tab is selected. The instruction fades in on each visit.
    private let isActive: Bool

    @State private var showsInstruction = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    init(
        audioRecorder: any AudioRecorder,
        transcriber: any Transcriber,
        noteStore: any NoteStore,
        openSettings: @escaping () -> Void,
        onRecordingFinished: @escaping (UUID) -> Void,
        instructionDelay: TimeInterval = 3,
        forcesReducedMotion: Bool = false,
        isActive: Bool = true
    ) {
        _model = StateObject(
            wrappedValue: RecordHomeViewModel(
                audioRecorder: audioRecorder,
                transcriber: transcriber,
                noteStore: noteStore
            )
        )
        self.openSettings = openSettings
        self.onRecordingFinished = onRecordingFinished
        self.instructionDelay = instructionDelay
        self.forcesReducedMotion = forcesReducedMotion
        self.isActive = isActive
    }

    private var reduceMotion: Bool {
        systemReduceMotion || forcesReducedMotion
    }

    var body: some View {
        ZStack {
            Color.tangentWash
                .ignoresSafeArea()

            orb
                .overlay(alignment: .bottom) {
                    statusBelowOrb
                        .padding(.top, 12)
                        .alignmentGuide(.bottom) { $0[.top] }
                }

            VStack {
                Spacer()
                if case .failed(let message) = model.phase {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color.tangentInk.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 32)
                        .transition(.opacity)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsToolbarButton(action: openSettings)
            }
        }
        .task(id: isActive) {
            guard isActive else {
                showsInstruction = false
                return
            }
            showsInstruction = false
            if instructionDelay > 0 {
                try? await Task.sleep(for: .seconds(instructionDelay))
            }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.4)) {
                showsInstruction = true
            }
        }
    }

    private var orb: some View {
        ZStack {
            TangentOrb(reduceMotion: reduceMotion)
                .frame(width: 240, height: 240)

            orbContent
        }
        .padding(24)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !model.isBusy else { return }
            Task { await model.startRecording() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(model.isRecording ? [] : .isButton)
        .accessibilityLabel(orbAccessibilityLabel)
        .accessibilityAction {
            guard !model.isBusy else { return }
            Task { await model.startRecording() }
        }
    }

    private var chromeAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.45)
    }

    private var showsTapToRecord: Bool {
        showsInstruction && !model.isRecording
    }

    private var orbContent: some View {
        stopButton
            .opacity(model.isRecording ? 1 : 0)
            .allowsHitTesting(model.isRecording)
            .animation(chromeAnimation, value: model.isRecording)
    }

    private var stopButton: some View {
        Button {
            Task {
                if let diaryID = await model.stopRecording() {
                    onRecordingFinished(diaryID)
                }
            }
        } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white)
                .frame(width: 34, height: 34)
                .padding(18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop recording")
    }

    private var statusBelowOrb: some View {
        ZStack {
            Text("Tap to record")
                .font(.body.weight(.medium))
                .opacity(showsTapToRecord ? 1 : 0)
                .accessibilityHidden(!showsTapToRecord)

            Text("Recording · \(model.formattedElapsed)")
                .font(.body.monospacedDigit())
                .opacity(model.isRecording ? 1 : 0)
                .accessibilityHidden(!model.isRecording)
                .accessibilityLabel("Recording, \(model.formattedElapsed)")
        }
        .foregroundStyle(Color.tangentInk.opacity(0.72))
        .allowsHitTesting(false)
        .animation(chromeAnimation, value: showsTapToRecord)
        .animation(chromeAnimation, value: model.isRecording)
    }

    private var orbAccessibilityLabel: String {
        switch model.phase {
        case .idle, .failed:
            return "Start recording"
        case .recording:
            return "Recording"
        }
    }
}

#Preview("Initial (instruction hidden)") {
    let container = try! TangentModelContainer.make(inMemory: true)
    NavigationStack {
        RecordHomeView(
            audioRecorder: UnavailableAudioRecorder(),
            transcriber: UnavailableTranscriber(),
            noteStore: SwiftDataNoteStore(modelContext: container.mainContext),
            openSettings: {},
            onRecordingFinished: { _ in },
            instructionDelay: 3600
        )
    }
}

#Preview("Ready (instruction visible)") {
    let container = try! TangentModelContainer.make(inMemory: true)
    NavigationStack {
        RecordHomeView(
            audioRecorder: UnavailableAudioRecorder(),
            transcriber: UnavailableTranscriber(),
            noteStore: SwiftDataNoteStore(modelContext: container.mainContext),
            openSettings: {},
            onRecordingFinished: { _ in },
            instructionDelay: 0
        )
    }
}

#Preview("Reduce Motion") {
    let container = try! TangentModelContainer.make(inMemory: true)
    NavigationStack {
        RecordHomeView(
            audioRecorder: UnavailableAudioRecorder(),
            transcriber: UnavailableTranscriber(),
            noteStore: SwiftDataNoteStore(modelContext: container.mainContext),
            openSettings: {},
            onRecordingFinished: { _ in },
            instructionDelay: 0,
            forcesReducedMotion: true
        )
    }
}
