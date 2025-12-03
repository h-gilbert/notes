import SwiftUI
import SwiftData

struct ArchivedNotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Query(
        filter: #Predicate<Note> { $0.isArchived },
        sort: [SortDescriptor(\Note.updatedAt, order: .reverse)]
    )
    private var archivedNotes: [Note]

    @State private var selectedNote: Note?
    @State private var syncService = SyncService.shared

    private var columnCount: Int {
        sizeClass == .compact ? 2 : 3
    }

    var body: some View {
        NavigationStack {
            Group {
                if archivedNotes.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        MasonryGrid(data: archivedNotes, columns: columnCount, spacing: Theme.Spacing.sm) { note in
                            NoteCardView(note: note)
                                .opacity(0.8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedNote = note
                                }
                                .contextMenu {
                                    Button {
                                        withAnimation {
                                            note.isArchived = false
                                            note.touch()
                                        }
                                        Task {
                                            await syncService.sync()
                                        }
                                    } label: {
                                        Label("Unarchive", systemImage: "tray.and.arrow.up")
                                    }

                                    Button(role: .destructive) {
                                        withAnimation {
                                            modelContext.delete(note)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.md)
                    }
                }
            }
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                if !archivedNotes.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                deleteAllArchived()
                            } label: {
                                Label("Delete all", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(item: $selectedNote) { note in
                if note.noteType == .checklist {
                    ChecklistEditorView(note: note)
                } else {
                    NoteEditorView(note: note)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No archived notes")
                .font(.title2)
                .fontWeight(.medium)

            Text("Archived notes will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deleteAllArchived() {
        for note in archivedNotes {
            modelContext.delete(note)
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, ChecklistItem.self, configurations: config)

    let note1 = Note(title: "Archived Note 1", content: "Some old content", isArchived: true)
    let note2 = Note(title: "Archived Note 2", content: "More old content", isArchived: true)

    container.mainContext.insert(note1)
    container.mainContext.insert(note2)

    return ArchivedNotesView()
        .modelContainer(container)
}
