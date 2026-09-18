struct AppDependencies {
    let noteStore: any NoteStore
    let audioRecorder: any AudioRecorder
    let transcriber: any Transcriber
    let reminderScheduler: any ReminderScheduler
    let summaryGenerator: any SummaryGenerator
    let modelCatalog: any ModelCatalog
}
