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
                .overlay(alignment: .top) {
                    promptingQuestion
                        .offset(y: -112)
                }
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
        .onTapGesture(perform: startRecordingIfIdle)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(model.isRecording ? [] : .isButton)
        .accessibilityLabel(orbAccessibilityLabel)
        .accessibilityAction {
            startRecordingIfIdle()
        }
    }

    private var promptingQuestion: some View {
        ZStack {
            if model.isRecording, let question = model.currentPromptQuestion {
                ZStack {
                    PromptCloud(reduceMotion: reduceMotion)
                        .frame(width: 350, height: 112)

                    Text(question)
                        .font(.system(.title3, weight: .regular))
                        .foregroundStyle(Color.tangentInk.opacity(0.74))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .frame(maxWidth: 300)
                        .padding(.horizontal, 20)
                }
                .id(question)
                .transition(.opacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Prompt: \(question)")
            } else if model.showsQuestionSuggestionOffer {
                Button {
                    Task { await model.acceptQuestionSuggestions() }
                } label: {
                    Text("Suggest prompts")
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(.gray)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityHint("Shows gentle questions while you record")
            }
        }
        .frame(width: 330, height: 80)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.8),
            value: model.currentPromptQuestion
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.8),
            value: model.showsQuestionSuggestionOffer
        )
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
            Button(action: startRecordingIfIdle) {
                Text("Tap to record")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(showsTapToRecord ? 1 : 0)
            .allowsHitTesting(showsTapToRecord)
            .accessibilityHidden(!showsTapToRecord)
            .accessibilityLabel("Tap to record")

            Text("Recording · \(model.formattedElapsed)")
                .font(.body.monospacedDigit())
                .opacity(model.isRecording ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(!model.isRecording)
                .accessibilityLabel("Recording, \(model.formattedElapsed)")
        }
        .foregroundStyle(Color.tangentInk.opacity(0.72))
        .animation(chromeAnimation, value: showsTapToRecord)
        .animation(chromeAnimation, value: model.isRecording)
    }

    private func startRecordingIfIdle() {
        guard !model.isBusy else { return }
        Task {
            await model.startRecording()
        }
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

/// A quiet, cloud-like backdrop for optional recording prompts. It is kept
/// deliberately pale so the recording orb remains the visual focal point.
private struct PromptCloud: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let shape = PromptCloudShape(time: time, deformation: reduceMotion ? 0 : 1)

            ZStack {
                shape
                    .fill(Color.white.opacity(0.42))
                    .blur(radius: 10)

                shape
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.52),
                                Color.tangentGold.opacity(0.14),
                                Color.tangentGold.opacity(0.025),
                                .clear,
                            ],
                            center: UnitPoint(
                                x: 0.38 + 0.04 * sin(time * 0.12),
                                y: 0.48 + 0.04 * cos(time * 0.1)
                            ),
                            startRadius: 2,
                            endRadius: 175
                        )
                    )
                    .blur(radius: 4)
            }
            .scaleEffect(
                x: 1 + (reduceMotion ? 0 : 0.008 * sin(time * 0.22)),
                y: 1 + (reduceMotion ? 0 : 0.012 * cos(time * 0.18))
            )
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct PromptCloudShape: Shape {
    let time: TimeInterval
    let deformation: Double

    func path(in rect: CGRect) -> Path {
        let waves: [(Double, Double)] = [
            (0.035, 0.0), (0.055, 1.2), (0.04, 2.4), (0.06, 3.5),
            (0.045, 4.7), (0.05, 5.5), (0.04, 0.8), (0.055, 2.0),
        ]
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let points = waves.enumerated().map { index, wave in
            let angle = 2 * Double.pi * Double(index) / Double(waves.count)
            let ripple = deformation * wave.0 * sin(time * 0.24 + wave.1)
            let horizontalRadius = rect.width * 0.46 * (1 + ripple)
            let verticalRadius = rect.height * 0.39 * (1 + ripple * 1.4)
            return CGPoint(
                x: center.x + horizontalRadius * cos(angle),
                y: center.y + verticalRadius * sin(angle)
            )
        }

        var path = Path()
        path.move(to: points[0])
        for index in points.indices {
            let p0 = points[(index - 1 + points.count) % points.count]
            let p1 = points[index]
            let p2 = points[(index + 1) % points.count]
            let p3 = points[(index + 2) % points.count]
            path.addCurve(
                to: p2,
                control1: CGPoint(
                    x: p1.x + (p2.x - p0.x) / 6,
                    y: p1.y + (p2.y - p0.y) / 6
                ),
                control2: CGPoint(
                    x: p2.x - (p3.x - p1.x) / 6,
                    y: p2.y - (p3.y - p1.y) / 6
                )
            )
        }
        path.closeSubpath()
        return path
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
