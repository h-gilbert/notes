import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var syncService = SyncService.shared
    @State private var authService = AuthService.shared
    @State private var showingDeleteConfirmation = false
    @State private var showingLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                syncSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete All Notes?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    deleteAllNotes()
                }
            } message: {
                Text("This will permanently delete all your notes. This action cannot be undone.")
            }
            .alert("Sign Out?", isPresented: $showingLogoutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    authService.logout()
                    dismiss()
                }
            } message: {
                Text("You will need to sign in again to sync your notes.")
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if let user = authService.currentUser {
                HStack {
                    Text("Signed in as")
                    Spacer()
                    Text(user.username)
                        .foregroundColor(.secondary)
                }
            }

            Button(role: .destructive) {
                showingLogoutConfirmation = true
            } label: {
                Text("Sign Out")
            }
        }
    }

    private var syncSection: some View {
        Section {
            HStack {
                Text("Sync Status")
                Spacer()
                syncStatusView
            }

            if let lastSync = syncService.lastSyncDate {
                HStack {
                    Text("Last Synced")
                    Spacer()
                    Text(lastSync, style: .relative)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                Task {
                    await syncService.sync()
                }
            } label: {
                HStack {
                    Text("Sync Now")
                    Spacer()
                    if syncService.syncState == .syncing {
                        ProgressView()
                    }
                }
            }
            .disabled(syncService.syncState == .syncing)
        } header: {
            Text("Sync")
        } footer: {
            Text("Notes are automatically synced when you have an internet connection.")
        }
    }

    @ViewBuilder
    private var syncStatusView: some View {
        switch syncService.syncState {
        case .idle:
            Label("Ready", systemImage: "checkmark.circle")
                .foregroundColor(.secondary)
                .labelStyle(.iconOnly)
        case .syncing:
            ProgressView()
        case .success:
            Label("Synced", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .labelStyle(.iconOnly)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .labelStyle(.iconOnly)
        }
    }

    private var dataSection: some View {
        Section("Data") {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Text("Delete All Notes")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Build")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func deleteAllNotes() {
        do {
            try modelContext.delete(model: Note.self)
            try modelContext.delete(model: ChecklistItem.self)
        } catch {
            print("Failed to delete notes: \(error)")
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, ChecklistItem.self, configurations: config)

    return SettingsView()
        .modelContainer(container)
}
