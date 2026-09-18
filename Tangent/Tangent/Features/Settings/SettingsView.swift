import SwiftUI

struct SettingsView: View {
    @StateObject private var model: SettingsViewModel

    init(
        noteStore: any NoteStore,
        reminderScheduler: any ReminderScheduler
    ) {
        _model = StateObject(
            wrappedValue: SettingsViewModel(
                noteStore: noteStore,
                reminderScheduler: reminderScheduler
            )
        )
    }

    var body: some View {
        Form {
            Section("Profile") {
                LabeledContent("Name", value: model.name)
                LabeledContent("Age", value: model.age)
                LabeledContent("Weight", value: model.weight)
                LabeledContent("Gender", value: model.gender)
                LabeledContent("Email", value: model.email)
            }

            Section("Health context") {
                LabeledContent("Health interests", value: model.healthInterests)
                LabeledContent("Health concerns", value: model.healthConcerns)
            }

            Section("Daily reminder") {
                Toggle(
                    "Reminder",
                    isOn: Binding(
                        get: { model.reminderEnabled },
                        set: { enabled in
                            Task { await model.setReminderEnabled(enabled) }
                        }
                    )
                )
                .disabled(model.isUpdatingReminder || model.isLoading)

                DatePicker(
                    "Time",
                    selection: Binding(
                        get: { model.dailyReminder },
                        set: { time in
                            Task { await model.setReminderTime(time) }
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .disabled(
                    !model.reminderEnabled
                        || model.isUpdatingReminder
                        || model.isLoading
                )
            }

            if let message = model.message {
                Section {
                    Text(message)
                        .foregroundStyle(Color.tangentInk.opacity(0.65))
                }
            }
        }
        .font(.system(.body))
        .foregroundStyle(Color.tangentInk)
        .scrollContentBackground(.hidden)
        .background(Color.tangentWash)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbarVisibility(.hidden, for: .tabBar)
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
        .task {
            await model.load()
        }
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
