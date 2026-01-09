import SwiftUI
import SwiftData

struct ChecklistEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var note: Note
    let isNewNote: Bool

    @State private var dragOffset: CGFloat = 0
    @State private var newItemText: String = ""
    @State private var syncService = SyncService.shared
    @State private var addItemRowID = "addItemRow"
    @State private var keyboardObserver = KeyboardObserver()
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNewItemFocused: Bool
    @FocusState private var focusedItemID: UUID?

    private let dismissThreshold: CGFloat = 120
    private let topPadding: CGFloat = 50

    init(note: Note, isNewNote: Bool = false) {
        self.note = note
        self.isNewNote = isNewNote
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                dragHandle
                checklistContent(geometry: geometry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.9),
                                Color.white.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Theme.Colors.shadowMedium, radius: 30, x: 0, y: -10)
            .offset(y: topPadding + dragOffset)
            .gesture(dragGesture)
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.8), value: dragOffset)
        }
        .background(Color.clear)
        .onAppear {
            if isNewNote {
                isTitleFocused = true
            }
        }
    }

    private var dragHandle: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Capsule()
                .fill(Theme.Colors.accent.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, Theme.Spacing.sm)

            HStack {
                Button {
                    saveAndDismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.Colors.accent)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Theme.Colors.accent.opacity(0.1))
                        )
                }

                Spacer()

                Menu {
                    pinButton
                    archiveButton
                    Divider()
                    if !note.checkedItems.isEmpty {
                        deleteCheckedButton
                    }
                    deleteButton
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.Colors.accent)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Theme.Colors.accent.opacity(0.1))
                        )
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xs)
        }
        .background(Theme.Colors.surface)
    }

    private var isAnyFieldFocused: Bool {
        isTitleFocused || isNewItemFocused || focusedItemID != nil
    }

    private func checklistContent(geometry: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    titleField

                    // Unchecked items
                    VStack(spacing: 2) {
                        ForEach(note.uncheckedItems) { item in
                            ChecklistItemRow(
                                item: item,
                                accentColor: Theme.Colors.accent,
                                isFocused: focusedItemID == item.id,
                                onDelete: { deleteItem(item) },
                                onToggle: { toggleItem(item) }
                            )
                            .id(item.id)
                        }
                        .onMove(perform: moveUncheckedItems)
                    }

                    // Add item row
                    addItemRow
                        .id(addItemRowID)

                    // Checked items section
                    if !note.checkedItems.isEmpty {
                        checkedItemsSection
                    }

                    // Tappable area to focus add item field
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(0, geometry.size.height - topPadding - 350 - keyboardObserver.keyboardHeight))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isNewItemFocused = true
                        }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, keyboardObserver.keyboardHeight > 0 ? keyboardObserver.keyboardHeight - geometry.safeAreaInsets.bottom + 60 : 0)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(minHeight: geometry.size.height - topPadding - 100)
            .simultaneousGesture(dismissDragGesture)
            .onChange(of: keyboardObserver.keyboardHeight) { oldValue, newValue in
                // When keyboard appears, scroll to show the focused field
                if newValue > oldValue && isAnyFieldFocused {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation {
                            if isNewItemFocused {
                                proxy.scrollTo(addItemRowID, anchor: .top)
                            } else if let itemID = focusedItemID {
                                proxy.scrollTo(itemID, anchor: .top)
                            }
                        }
                    }
                }
            }
            .onChange(of: focusedItemID) { _, itemID in
                if let itemID = itemID, keyboardObserver.keyboardHeight > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo(itemID, anchor: .top)
                        }
                    }
                }
            }
            .onChange(of: newItemText) { _, _ in
                if isNewItemFocused && keyboardObserver.keyboardHeight > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(addItemRowID, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private var dismissDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let isDraggingDown = value.translation.height > 0
                let isSignificantDrag = value.translation.height > 10

                if isDraggingDown && isSignificantDrag && !isAnyFieldFocused {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > dismissThreshold && !isAnyFieldFocused {
                    saveAndDismiss()
                } else {
                    withAnimation(.spring(response: 0.3)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > dismissThreshold {
                    saveAndDismiss()
                } else {
                    withAnimation(.spring(response: 0.3)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private var titleField: some View {
        TextField("Title", text: $note.title, axis: .vertical)
            .font(Theme.Typography.displayMedium())
            .foregroundColor(Theme.Colors.textPrimary)
            .focused($isTitleFocused)
            .onChange(of: note.title) { _, _ in
                note.touch()
            }
    }

    private var addItemRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .strokeBorder(Theme.Colors.accent.opacity(0.4), lineWidth: 1.5)
                .frame(width: 22, height: 22)

            TextField("Add item", text: $newItemText)
                .font(Theme.Typography.body())
                .foregroundColor(Theme.Colors.textPrimary)
                .focused($isNewItemFocused)
                .onSubmit {
                    addNewItem()
                }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var checkedItemsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("\(note.checkedItems.count) completed")
                    .font(Theme.Typography.label())
                    .foregroundColor(Theme.Colors.textTertiary)
                Spacer()
            }
            .padding(.top, Theme.Spacing.sm)

            Rectangle()
                .fill(Theme.Colors.accent.opacity(0.2))
                .frame(height: 1)

            ForEach(note.checkedItems) { item in
                ChecklistItemRow(
                    item: item,
                    accentColor: Theme.Colors.accent,
                    isFocused: focusedItemID == item.id,
                    onDelete: { deleteItem(item) },
                    onToggle: { toggleItem(item) }
                )
            }
        }
    }

    private var pinButton: some View {
        Button {
            withAnimation(Theme.Animation.springy) {
                note.isPinned.toggle()
                note.touch()
            }
        } label: {
            Label(
                note.isPinned ? "Unpin" : "Pin",
                systemImage: note.isPinned ? "pin.slash" : "pin"
            )
        }
    }

    private var archiveButton: some View {
        Button {
            withAnimation(Theme.Animation.smooth) {
                note.isArchived = true
                note.touch()
            }
            dismiss()
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
    }

    private var deleteCheckedButton: some View {
        Button {
            withAnimation(Theme.Animation.smooth) {
                for item in note.checkedItems {
                    modelContext.delete(item)
                }
                note.touch()
            }
        } label: {
            Label("Clear completed", systemImage: "checkmark.circle")
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            // Track deletion for sync before deleting
            if let serverID = note.serverID {
                syncService.markNoteAsDeleted(serverID: serverID)
            }
            modelContext.delete(note)
            Task {
                await syncService.sync()
            }
            dismiss()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func addNewItem() {
        guard !newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let maxOrder = note.uncheckedItems.map(\.sortOrder).max() ?? -1
        let item = ChecklistItem(
            text: newItemText,
            sortOrder: maxOrder + 1,
            note: note
        )

        if note.checklistItems == nil {
            note.checklistItems = []
        }
        note.checklistItems?.append(item)
        note.touch()

        newItemText = ""
        isNewItemFocused = true
    }

    private func deleteItem(_ item: ChecklistItem) {
        withAnimation(Theme.Animation.smooth) {
            modelContext.delete(item)
            note.touch()
        }
    }

    private func toggleItem(_ item: ChecklistItem) {
        withAnimation(Theme.Animation.springy) {
            item.toggle()
        }
    }

    private func moveUncheckedItems(from source: IndexSet, to destination: Int) {
        var items = note.uncheckedItems
        items.move(fromOffsets: source, toOffset: destination)

        for (index, item) in items.enumerated() {
            item.sortOrder = index
        }
        note.touch()
    }

    private func saveAndDismiss() {
        // Save any pending text in the add item field
        if !newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addNewItem()
        }

        if !note.isValid {
            if isNewNote {
                // Delete empty new notes
                modelContext.delete(note)
            } else {
                // Archive existing notes that become empty
                note.isArchived = true
                note.touch()
            }
        }
        // Sync changes to server immediately
        Task {
            await syncService.sync()
        }
        dismiss()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, ChecklistItem.self, configurations: config)
    let note = Note(title: "Weekend Goals", noteType: .checklist)
    container.mainContext.insert(note)

    let item1 = ChecklistItem(text: "Morning yoga", sortOrder: 0, note: note)
    let item2 = ChecklistItem(text: "Read a chapter", sortOrder: 1, note: note)
    let item3 = ChecklistItem(text: "Call mom", isCompleted: true, sortOrder: 2, note: note)
    container.mainContext.insert(item1)
    container.mainContext.insert(item2)
    container.mainContext.insert(item3)
    note.checklistItems = [item1, item2, item3]

    return ChecklistEditorView(note: note)
        .modelContainer(container)
}
