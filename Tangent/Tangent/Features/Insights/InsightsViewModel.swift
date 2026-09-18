import Combine
import Foundation

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var insights: [Insight] = []
    @Published private(set) var isLoading = true
    @Published private(set) var loadError: String?

    private let noteStore: any NoteStore

    init(noteStore: any NoteStore) {
        self.noteStore = noteStore
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            insights = try await noteStore.insights()
            loadError = nil
        } catch {
            loadError = "Your insights could not be loaded."
        }
    }
}
