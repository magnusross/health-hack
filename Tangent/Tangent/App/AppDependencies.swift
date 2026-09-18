struct AppDependencies {
    let noteStore: any NoteStore
    let audioRecorder: any AudioRecorder
    let transcriber: any Transcriber
    let healthModel: any HealthLanguageModel
    let modelCatalog: any ModelCatalog
    let reminderScheduler: any ReminderScheduler
}
