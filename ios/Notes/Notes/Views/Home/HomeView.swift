import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Query(
        filter: #Predicate<Note> { !$0.isArchived },
        sort: [SortDescriptor(\Note.sortOrder)]
    )
    private var allNotes: [Note]

    @State private var selectedNote: Note?
    @State private var isCreatingNote = false
    @State private var newNote: Note?
    @State private var showingArchive = false
    @State private var showingSettings = false
    @State private var isReorderMode = false
    @State private var syncService = SyncService.shared

    @Namespace private var animation

    private var columnCount: Int {
        sizeClass == .compact ? 2 : 3
    }

    private var pinnedNotes: [Note] {
        allNotes.filter { $0.isPinned }
    }

    private var unpinnedNotes: [Note] {
        allNotes.filter { !$0.isPinned }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background
                Theme.Colors.background
                    .ignoresSafeArea()

                if allNotes.isEmpty {
                    emptyStateView
                        .padding(.bottom, 100)
                } else if isReorderMode {
                    // Reorder mode - single column list with drag handles
                    List {
                        if !pinnedNotes.isEmpty {
                            Section {
                                ForEach(pinnedNotes) { note in
                                    reorderRow(for: note)
                                }
                                .onMove(perform: movePinnedNotes)
                            } header: {
                                Text("PINNED")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.Colors.accent)
                            }
                        }

                        if !unpinnedNotes.isEmpty {
                            Section {
                                ForEach(unpinnedNotes) { note in
                                    reorderRow(for: note)
                                }
                                .onMove(perform: moveUnpinnedNotes)
                            } header: {
                                Text("NOTES")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Theme.Colors.background)
                    .environment(\.editMode, .constant(.active))
                } else {
                    // Normal masonry view
                    ScrollView {
                        VStack(spacing: Theme.Spacing.lg) {
                            if !pinnedNotes.isEmpty {
                                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                    pinnedSectionHeader
                                    MasonryGrid(data: pinnedNotes, columns: columnCount, spacing: Theme.Spacing.sm) { note in
                                        noteCard(for: note)
                                    }
                                    .animation(Theme.Animation.smooth, value: pinnedNotes.map(\.id))
                                }
                            }

                            if !unpinnedNotes.isEmpty {
                                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                    if !pinnedNotes.isEmpty {
                                        othersSectionHeader
                                    }
                                    MasonryGrid(data: unpinnedNotes, columns: columnCount, spacing: Theme.Spacing.sm) { note in
                                        noteCard(for: note)
                                    }
                                    .animation(Theme.Animation.smooth, value: unpinnedNotes.map(\.id))
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.bottom, 100)
                    }
                }

                createNoteBar
            }
            .navigationTitle("Notes")
            .toolbarBackground(Theme.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !allNotes.isEmpty {
                        Button {
                            withAnimation {
                                isReorderMode.toggle()
                            }
                        } label: {
                            if isReorderMode {
                                Text("Done")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Theme.Colors.accent)
                            } else {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                    }

                    if !isReorderMode {
                        Button {
                            showingArchive = true
                        } label: {
                            Image(systemName: "archivebox")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
            .fullScreenCover(item: $selectedNote) { note in
                if note.noteType == .checklist {
                    ChecklistEditorView(note: note)
                        .background(ClearBackgroundView())
                } else {
                    NoteEditorView(note: note)
                        .background(ClearBackgroundView())
                }
            }
            .fullScreenCover(isPresented: $isCreatingNote) {
                if let note = newNote {
                    if note.noteType == .checklist {
                        ChecklistEditorView(note: note, isNewNote: true)
                            .background(ClearBackgroundView())
                    } else {
                        NoteEditorView(note: note, isNewNote: true)
                            .background(ClearBackgroundView())
                    }
                }
            }
            .sheet(isPresented: $showingArchive) {
                ArchivedNotesView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .task {
                // Configure sync service with model context and trigger initial sync
                if let token = UserDefaults.standard.string(forKey: Constants.Storage.authTokenKey) {
                    await syncService.configure(
                        modelContext: modelContext,
                        baseURL: Constants.API.baseURL,
                        authToken: token
                    )

                    // Configure and connect WebSocket for real-time updates
                    WebSocketService.shared.configure(modelContext: modelContext)
                    await WebSocketService.shared.connect(token: token)

                    await syncService.sync()
                    syncService.startAutoSync()
                }
            }
            .onDisappear {
                syncService.stopAutoSync()
            }
        }
    }

    // MARK: - Section Headers

    private var pinnedSectionHeader: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("PINNED")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundColor(Theme.Colors.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Theme.Colors.accentLight.opacity(0.4))
            )

            Spacer()

            Text("\(pinnedNotes.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.accent.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Circle()
                        .fill(Theme.Colors.accentLight.opacity(0.3))
                )
        }
        .padding(.horizontal, Theme.Spacing.md)
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
    }

    private var othersSectionHeader: some View {
        HStack(spacing: 0) {
            Text("OTHER NOTES")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1)
                .foregroundColor(Theme.Colors.textTertiary)

            Spacer()

            Text("\(unpinnedNotes.count)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary.opacity(0.8))
        }
        .padding(.horizontal, Theme.Spacing.md)
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 12, trailing: 0))
    }

    // MARK: - Note Card

    @ViewBuilder
    private func noteCard(for note: Note) -> some View {
        NoteCardView(note: note)
            .matchedGeometryEffect(id: note.id, in: animation)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedNote = note
            }
            .contextMenu {
                Button {
                    withAnimation(Theme.Animation.smooth) {
                        note.isPinned.toggle()
                        note.touch()
                    }
                    Task {
                        await syncService.sync()
                    }
                } label: {
                    Label(
                        note.isPinned ? "Unpin" : "Pin",
                        systemImage: note.isPinned ? "pin.slash" : "pin"
                    )
                }

                Button {
                    withAnimation(Theme.Animation.smooth) {
                        note.isArchived = true
                        note.touch()
                    }
                    Task {
                        await syncService.sync()
                    }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }

                Button(role: .destructive) {
                    // Track deletion for sync before deleting
                    if let serverID = note.serverID {
                        syncService.markNoteAsDeleted(serverID: serverID)
                    }
                    withAnimation(Theme.Animation.smooth) {
                        modelContext.delete(note)
                    }
                    Task {
                        await syncService.sync()
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    // MARK: - Create Note Bar

    private var createNoteBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Theme.Colors.shadowLight, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 1)

            HStack(spacing: Theme.Spacing.sm) {
                // Create note button
                Button {
                    createNewNote(ofType: .note)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(Theme.Colors.accent)

                        Text("Take a note...")
                            .font(Theme.Typography.body())
                            .foregroundColor(Theme.Colors.textTertiary)

                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                            .fill(Theme.Colors.surface)
                            .shadow(color: Theme.Colors.shadowLight, radius: 8, x: 0, y: 2)
                    )
                }
                .buttonStyle(.plain)

                // Create checklist button
                Button {
                    createNewNote(ofType: .checklist)
                } label: {
                    Image(systemName: "checklist")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Theme.Colors.accent)
                        .frame(width: 52, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                                .fill(Theme.Colors.surface)
                                .shadow(color: Theme.Colors.shadowLight, radius: 8, x: 0, y: 2)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Theme.Colors.background
                    .opacity(0.95)
            )
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accentLight.opacity(0.5))
                    .frame(width: 120, height: 120)
                    .offset(x: -20, y: 10)

                Circle()
                    .fill(Color(hex: "D6E5F5").opacity(0.6))
                    .frame(width: 80, height: 80)
                    .offset(x: 40, y: -20)

                Circle()
                    .fill(Color(hex: "E8DFF5").opacity(0.5))
                    .frame(width: 60, height: 60)
                    .offset(x: 30, y: 30)

                Image(systemName: "note.text")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(Theme.Colors.accent)
            }
            .frame(height: 140)

            VStack(spacing: Theme.Spacing.xs) {
                Text("Your canvas awaits")
                    .font(Theme.Typography.displayMedium())
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("Tap below to capture your first thought")
                    .font(Theme.Typography.body())
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Reorder Row

    @ViewBuilder
    private func reorderRow(for note: Note) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                if !note.content.isEmpty {
                    Text(note.content)
                        .font(.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                } else if note.noteType == .checklist {
                    let itemCount = note.checklistItems?.count ?? 0
                    Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Reorder Actions

    private func movePinnedNotes(from source: IndexSet, to destination: Int) {
        var reorderedNotes = pinnedNotes
        reorderedNotes.move(fromOffsets: source, toOffset: destination)

        for (index, note) in reorderedNotes.enumerated() {
            let newSortOrder = -(reorderedNotes.count - index)
            if note.sortOrder != newSortOrder {
                note.sortOrder = newSortOrder
                note.touch()
            }
        }

        Task {
            await syncService.sync()
        }
    }

    private func moveUnpinnedNotes(from source: IndexSet, to destination: Int) {
        var reorderedNotes = unpinnedNotes
        reorderedNotes.move(fromOffsets: source, toOffset: destination)

        for (index, note) in reorderedNotes.enumerated() {
            if note.sortOrder != index {
                note.sortOrder = index
                note.touch()
            }
        }

        Task {
            await syncService.sync()
        }
    }

    // MARK: - Actions

    private func createNewNote(ofType noteType: NoteType = .note) {
        // New notes should appear at the top of the unpinned section
        let minSortOrder = unpinnedNotes.map(\.sortOrder).min() ?? 0
        let note = Note(
            noteType: noteType,
            sortOrder: minSortOrder - 1
        )
        modelContext.insert(note)
        newNote = note
        isCreatingNote = true
    }

}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, ChecklistItem.self, configurations: config)

    let note1 = Note(title: "Morning Reflections", content: "A quiet moment to gather thoughts before the day begins.", isPinned: true, sortOrder: 0)
    let note2 = Note(title: "Design Inspiration", content: "Soft pastels, rounded corners, gentle shadows - the essence of calm.", sortOrder: 1)
    let note3 = Note(title: "Weekend Plans", noteType: .checklist, sortOrder: 2)
    let note4 = Note(title: "Book Notes", content: "Chapter 3: The importance of negative space in visual design.", sortOrder: 3)

    container.mainContext.insert(note1)
    container.mainContext.insert(note2)
    container.mainContext.insert(note3)
    container.mainContext.insert(note4)

    let item1 = ChecklistItem(text: "Visit the farmers market", sortOrder: 0, note: note3)
    let item2 = ChecklistItem(text: "Brunch with friends", sortOrder: 1, note: note3)
    let item3 = ChecklistItem(text: "Evening walk", isCompleted: true, sortOrder: 2, note: note3)
    container.mainContext.insert(item1)
    container.mainContext.insert(item2)
    container.mainContext.insert(item3)
    note3.checklistItems = [item1, item2, item3]

    return HomeView()
        .modelContainer(container)
}
