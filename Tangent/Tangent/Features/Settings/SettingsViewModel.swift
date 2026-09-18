import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var name = "—"
    @Published private(set) var age = "—"
    @Published private(set) var weight = "—"
    @Published private(set) var gender = "—"
    @Published private(set) var healthInterests = "—"
    @Published private(set) var healthConcerns = "—"
    @Published private(set) var email = "—"
    @Published private(set) var reminderEnabled = true
    @Published private(set) var dailyReminder = Date()

    @Published private(set) var profileID: UUID?
    @Published private(set) var isLoading = true
    @Published private(set) var isUpdatingReminder = false
    @Published private(set) var message: String?
    @Published var exportDocument: SettingsExportDocument?
    @Published var showsExporter = false

    private let noteStore: any NoteStore
    private let reminderScheduler: any ReminderScheduler
    private var profile: PatientProfile?

    init(
        noteStore: any NoteStore,
        reminderScheduler: any ReminderScheduler
    ) {
        self.noteStore = noteStore
        self.reminderScheduler = reminderScheduler
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let profile = try await noteStore.patientProfiles().first else {
                message = "No patient profile is available."
                return
            }
            apply(profile)
            if let reminder = profile.dailyReminder {
                try await reminderScheduler.scheduleDailyReminder(at: reminder)
            }
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func setReminderEnabled(_ enabled: Bool) async {
        guard var profile, !isUpdatingReminder else { return }
        let previousReminder = profile.dailyReminder
        reminderEnabled = enabled
        isUpdatingReminder = true
        defer { isUpdatingReminder = false }

        do {
            if enabled {
                profile.dailyReminder = dailyReminder
                try await reminderScheduler.scheduleDailyReminder(
                    at: dailyReminder
                )
            } else {
                profile.dailyReminder = nil
                reminderScheduler.cancelDailyReminder()
            }
            try await noteStore.savePatientProfile(profile)
            self.profile = profile
            message = enabled
                ? "Daily reminder scheduled."
                : "Daily reminder turned off."
        } catch {
            reminderEnabled = previousReminder != nil
            profile.dailyReminder = previousReminder
            self.profile = profile
            message = error.localizedDescription
        }
    }

    func prepareExport() async {
        guard let profileID else { return }
        do {
            let entries = try await noteStore.diaryEntries(patientID: profileID)
            exportDocument = SettingsExportDocument(
                data: DiaryXMLExporter.makeDocument(
                    entries: entries,
                    patientID: profileID
                )
            )
            showsExporter = true
            message = nil
        } catch {
            message = "Your diary could not be prepared for export."
        }
    }

    func exportCompleted(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            message = "Diary exported."
        case .failure:
            message = "Your diary could not be exported."
        }
    }

    var formattedReminderTime: String {
        guard reminderEnabled else { return "—" }
        return dailyReminder.formatted(date: .omitted, time: .shortened)
    }

    private func apply(_ profile: PatientProfile) {
        self.profile = profile
        profileID = profile.id
        name = profile.name
        age = profile.age.map(String.init) ?? "—"
        weight = profile.weight.map {
            $0.formatted(.number.precision(.fractionLength(0...2))) + " kg"
        } ?? "—"
        gender = profile.gender.isEmpty ? "—" : profile.gender
        healthInterests = profile.healthInterests.isEmpty
            ? "—"
            : profile.healthInterests.joined(separator: ", ")
        healthConcerns = profile.healthConcerns.isEmpty
            ? "—"
            : profile.healthConcerns.joined(separator: ", ")
        email = profile.email.isEmpty ? "—" : profile.email
        reminderEnabled = profile.dailyReminder != nil
        dailyReminder = profile.dailyReminder ?? Date()
    }
}
