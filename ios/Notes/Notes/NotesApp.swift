import SwiftUI
import SwiftData

@main
struct NotesApp: App {
    @State private var authService = AuthService.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Note.self,
            ChecklistItem.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Migration failed - delete old store and create fresh one
            // This happens when schema changes are incompatible (e.g., String → UUID)
            print("Migration failed, attempting to delete old store: \(error)")

            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            let fileManager = FileManager.default

            // Delete all store-related files
            for suffix in ["", "-shm", "-wal"] {
                let fileURL = url.deletingLastPathComponent().appending(path: "default.store\(suffix)")
                try? fileManager.removeItem(at: fileURL)
            }

            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                HomeView()
            } else {
                LoginView()
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
