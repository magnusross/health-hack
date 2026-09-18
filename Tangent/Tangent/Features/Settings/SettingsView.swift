import SwiftUI

struct SettingsView: View {
    @StateObject private var model: SettingsViewModel

    init(
        noteStore: any NoteStore,
        reminderScheduler: any ReminderScheduler,
        modelCatalog: (any ModelCatalog)? = nil
    ) {
        _model = StateObject(
            wrappedValue: SettingsViewModel(
                noteStore: noteStore,
                reminderScheduler: reminderScheduler,
                modelCatalog: modelCatalog
            )
        )
    }

    var body: some View {
        Form {
            profileSection
            healthContextSection
            reminderSection
            modelSection
            messageSection
        }
        .font(.system(.body))
        .foregroundStyle(Color.tangentInk)
        .scrollContentBackground(.hidden)
        .background(Color.tangentWash)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {}
                    .accessibilityHint("Profile editing is not available yet")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await model.prepareExport() }
            } label: {
                Label("Export diary", systemImage: "square.and.arrow.up")
                    .font(.system(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.tangentPurple)
            .disabled(model.profileID == nil || model.isLoading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .fileExporter(
            isPresented: $model.showsExporter,
            document: model.exportDocument,
            contentType: .tangentDiaryXML,
            defaultFilename: "Tangent Diary"
        ) { result in
            model.exportCompleted(result)
        }
        .confirmationDialog(
            downloadPromptTitle,
            isPresented: Binding(
                get: { model.pendingDownload != nil },
                set: { if !$0 { model.pendingDownload = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Download") {
                Task { await model.confirmPendingDownload() }
            }
            Button("Not now", role: .cancel) {
                model.pendingDownload = nil
            }
        }
        .task {
            await model.load()
            await model.loadModels()
        }
    }

    private var profileSection: some View {
        Section("Profile") {
            LabeledContent("Name", value: model.name)
            LabeledContent("Age", value: model.age)
            LabeledContent("Weight", value: model.weight)
            LabeledContent("Gender", value: model.gender)
            LabeledContent("Email", value: model.email)
        }
    }

    private var healthContextSection: some View {
        Section("Health context") {
            LabeledContent("Health interests", value: model.healthInterests)
            LabeledContent("Health concerns", value: model.healthConcerns)
        }
    }

    private var reminderSection: some View {
        Section("Daily reminder") {
            Toggle("Reminder", isOn: reminderBinding)
                .disabled(model.isUpdatingReminder || model.isLoading)
            LabeledContent("Time", value: model.formattedReminderTime)
        }
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { model.reminderEnabled },
            set: { enabled in
                Task { await model.setReminderEnabled(enabled) }
            }
        )
    }

    private var modelSection: some View {
        Section {
            ForEach(SummaryModelID.allCases) { summaryModel in
                modelRow(summaryModel)
            }
        } header: {
            Text("Model")
        } footer: {
            Text("Summaries are written on this device. Nothing you say is sent anywhere.")
        }
    }

    @ViewBuilder
    private var messageSection: some View {
        if let message = model.message {
            Section {
                Text(message)
                    .foregroundStyle(Color.tangentInk.opacity(0.65))
            }
        }
    }

    private var downloadPromptTitle: String {
        guard let pending = model.pendingDownload else { return "" }
        let size = ByteCountFormatter.string(
            fromByteCount: pending.approximateDownloadBytes,
            countStyle: .file
        )
        return "\(pending.displayName) is about \(size). Download it now?"
    }

    @ViewBuilder
    private func modelRow(_ summaryModel: SummaryModelID) -> some View {
        let state = model.modelStates[summaryModel] ?? .notDownloaded
        let isSelected = model.selectedModel == summaryModel

        VStack(alignment: .leading, spacing: 8) {
            Button {
                model.chooseModel(summaryModel)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summaryModel.displayName)
                            .font(.system(.body, weight: isSelected ? .semibold : .regular))
                        Text(summaryModel.summary)
                            .font(.footnote)
                            .foregroundStyle(Color.tangentInk.opacity(0.6))
                        Text(model.stateDescription(for: summaryModel))
                            .font(.footnote)
                            .foregroundStyle(Color.tangentInk.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.tangentPurple)
                            .accessibilityLabel("Selected")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if case .downloading(let fraction) = state {
                ProgressView(value: fraction)
                    .tint(Color.tangentPurple)
                Button("Cancel download") {
                    Task { await model.cancelDownload(summaryModel) }
                }
                .font(.footnote)
                .foregroundStyle(Color.tangentPurple)
            } else if state.isReady {
                Button("Remove from device", role: .destructive) {
                    Task { await model.deleteModel(summaryModel) }
                }
                .font(.footnote)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    let container = try! TangentModelContainer.make(inMemory: true)
    NavigationStack {
        SettingsView(
            noteStore: SwiftDataNoteStore(modelContext: container.mainContext),
            reminderScheduler: UnavailableReminderScheduler()
        )
    }
}
