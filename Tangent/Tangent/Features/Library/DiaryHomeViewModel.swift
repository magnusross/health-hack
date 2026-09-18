import Combine
import Foundation

struct DiaryTimelineDay: Identifiable, Equatable {
    let date: Date
    let entry: DiaryEntry?

    var id: Date { date }
}

@MainActor
final class DiaryHomeViewModel: ObservableObject {
    @Published private(set) var days: [DiaryTimelineDay]
    @Published private(set) var loadError: String?

    private let noteStore: any NoteStore
    private let calendar: Calendar

    init(
        noteStore: any NoteStore,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.noteStore = noteStore
        self.calendar = calendar
        days = Self.makeTimeline(entries: [], today: Date(), calendar: calendar)
    }

    func load() async {
        do {
            let currentPatient = try await noteStore.patientProfiles().first
            let entries: [DiaryEntry]
            if let currentPatient {
                entries = try await noteStore.diaryEntries(
                    patientID: currentPatient.id
                )
            } else {
                entries = []
            }

            days = Self.makeTimeline(
                entries: entries,
                today: Date(),
                calendar: calendar
            )
            loadError = nil
        } catch {
            loadError = "Your diary could not be loaded."
        }
    }

    nonisolated static func makeTimeline(
        entries: [DiaryEntry],
        today: Date,
        calendar: Calendar
    ) -> [DiaryTimelineDay] {
        let today = calendar.startOfDay(for: today)
        let entriesThroughToday = entries.filter {
            calendar.startOfDay(for: $0.day) <= today
        }
        let entriesByDay = Dictionary(grouping: entriesThroughToday) {
            calendar.startOfDay(for: $0.day)
        }
        let firstDay = entriesByDay.keys.min() ?? today

        var result: [DiaryTimelineDay] = []
        var date = firstDay

        while date <= today {
            let entry = entriesByDay[date]?.max { $0.day < $1.day }
            result.append(DiaryTimelineDay(date: date, entry: entry))

            guard let nextDate = calendar.date(
                byAdding: .day,
                value: 1,
                to: date
            ) else {
                break
            }
            date = nextDate
        }

        return result
    }
}
