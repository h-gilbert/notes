import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var note: Note
    let isNewNote: Bool

    @State private var dragOffset: CGFloat = 0
    @State private var syncService = SyncService.shared
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isContentFocused: Bool

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
                noteContent(geometry: geometry)
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
            // Pill handle
            Capsule()
                .fill(Theme.Colors.accent.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, Theme.Spacing.sm)

            // Toolbar
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

    private func noteContent(geometry: GeometryProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                titleField
                contentField

                // Tappable area to focus content field
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(0, geometry.size.height - topPadding - 250))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isContentFocused = true
                    }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(minHeight: geometry.size.height - topPadding - 100)
        .simultaneousGesture(dismissDragGesture)
    }

    private var dismissDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Only trigger dismiss gesture when dragging down and keyboard is not active
                // or when dragging from the top portion of the view
                let isDraggingDown = value.translation.height > 0
                let isSignificantDrag = value.translation.height > 10

                if isDraggingDown && isSignificantDrag && !isTitleFocused && !isContentFocused {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > dismissThreshold && !isTitleFocused && !isContentFocused {
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

    private var contentField: some View {
        TextField("Start writing...", text: $note.content, axis: .vertical)
            .font(Theme.Typography.body())
            .foregroundColor(Theme.Colors.textSecondary)
            .lineSpacing(4)
            .focused($isContentFocused)
            .onChange(of: note.content) { _, _ in
                note.touch()
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
            withAnimation(Theme.Animation.gentle) {
                note.isArchived = true
                note.touch()
            }
            dismiss()
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            modelContext.delete(note)
            dismiss()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func saveAndDismiss() {
        if !note.isValid && isNewNote {
            modelContext.delete(note)
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
    let container = try! ModelContainer(for: Note.self, configurations: config)
    let note = Note(title: "Morning Thoughts", content: "The gentle light of dawn brings clarity to the mind.")
    container.mainContext.insert(note)

    return NoteEditorView(note: note)
        .modelContainer(container)
}
