import SwiftUI
import SwiftData

struct NoteCardView: View {
    let note: Note

    private let minHeight: CGFloat = 90
    private let maxHeight: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Title
            if !note.title.isEmpty {
                Text(note.title)
                    .font(Theme.Typography.headline())
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(2)
            }

            if note.noteType == .checklist {
                checklistPreview
            } else if !note.content.isEmpty {
                Text(note.content)
                    .font(note.title.isEmpty ? Theme.Typography.body() : Theme.Typography.bodySmall())
                    .foregroundColor(note.title.isEmpty ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    .lineLimit(note.title.isEmpty ? 12 : 8)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .frame(minHeight: minHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(note.isPinned ? Theme.Colors.accentLight.opacity(0.15) : Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(
                    note.isPinned
                        ? LinearGradient(
                            colors: [
                                Theme.Colors.accent.opacity(0.4),
                                Theme.Colors.accent.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          )
                        : LinearGradient(
                            colors: [
                                Color.white.opacity(0.8),
                                Color.white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          ),
                    lineWidth: note.isPinned ? 1.5 : 1
                )
        )
        .shadow(color: note.isPinned ? Theme.Colors.accent.opacity(0.15) : Theme.Colors.shadowLight, radius: 8, x: 0, y: 4)
        .shadow(color: Theme.Colors.shadowMedium, radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    private var checklistPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(note.uncheckedItems.prefix(4)) { item in
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(Theme.Colors.accent.opacity(0.6), lineWidth: 1.5)
                        .frame(width: 16, height: 16)

                    Text(item.text)
                        .font(Theme.Typography.bodySmall())
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                }
            }

            if note.uncheckedItems.count > 4 {
                Text("+\(note.uncheckedItems.count - 4) more")
                    .font(Theme.Typography.caption())
                    .foregroundColor(Theme.Colors.textTertiary)
                    .padding(.leading, 26)
            }

            if !note.checkedItems.isEmpty {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Theme.Colors.accent.opacity(0.2))
                            .frame(width: 16, height: 16)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Theme.Colors.accent)
                    }

                    Text("\(note.checkedItems.count) completed")
                        .font(Theme.Typography.caption())
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .padding(.top, 4)
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, ChecklistItem.self, configurations: config)

    let note1 = Note(
        title: "Morning Thoughts",
        content: "The soft light filters through, bringing a sense of calm to the day ahead."
    )

    let note2 = Note(
        title: "Grocery Run",
        noteType: .checklist
    )

    let note3 = Note(
        title: "Design Ideas",
        content: "Explore pastel palettes and soft shadows for the new interface.",
        isPinned: true
    )

    container.mainContext.insert(note1)
    container.mainContext.insert(note2)
    container.mainContext.insert(note3)

    let item1 = ChecklistItem(text: "Fresh bread", sortOrder: 0, note: note2)
    let item2 = ChecklistItem(text: "Almond milk", sortOrder: 1, note: note2)
    let item3 = ChecklistItem(text: "Avocados", isCompleted: true, sortOrder: 2, note: note2)
    container.mainContext.insert(item1)
    container.mainContext.insert(item2)
    container.mainContext.insert(item3)
    note2.checklistItems = [item1, item2, item3]

    return ScrollView {
        VStack(spacing: 16) {
            NoteCardView(note: note3)
            NoteCardView(note: note1)
            NoteCardView(note: note2)
        }
        .padding()
    }
    .background(Theme.Colors.background)
    .modelContainer(container)
}
