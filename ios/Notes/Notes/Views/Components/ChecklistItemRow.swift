import SwiftUI
import SwiftData

struct ChecklistItemRow: View {
    @Bindable var item: ChecklistItem
    var accentColor: Color
    var isFocused: Bool

    let onDelete: () -> Void
    let onToggle: () -> Void

    init(
        item: ChecklistItem,
        accentColor: Color = Theme.Colors.textSecondary,
        isFocused: Bool,
        onDelete: @escaping () -> Void,
        onToggle: @escaping () -> Void
    ) {
        self.item = item
        self.accentColor = accentColor
        self.isFocused = isFocused
        self.onDelete = onDelete
        self.onToggle = onToggle
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            item.isCompleted ? accentColor : accentColor.opacity(0.4),
                            lineWidth: 1.5
                        )
                        .frame(width: 22, height: 22)

                    if item.isCompleted {
                        Circle()
                            .fill(accentColor.opacity(0.2))
                            .frame(width: 22, height: 22)

                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            TextField("", text: $item.text, axis: .vertical)
                .font(Theme.Typography.body())
                .lineLimit(1...10)
                .strikethrough(item.isCompleted, color: Theme.Colors.textTertiary)
                .foregroundColor(item.isCompleted ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                .onChange(of: item.text) { _, _ in
                    item.updatedAt = Date()
                    item.note?.touch()
                }

            if isFocused {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
        .animation(Theme.Animation.quick, value: item.isCompleted)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, ChecklistItem.self, configurations: config)
    let item = ChecklistItem(text: "Sample item")
    container.mainContext.insert(item)

    return VStack(spacing: 0) {
        ChecklistItemRow(
            item: item,
            accentColor: Color(hex: "6BA377"),
            isFocused: false,
            onDelete: {},
            onToggle: {}
        )
        ChecklistItemRow(
            item: ChecklistItem(text: "Completed item", isCompleted: true),
            accentColor: Color(hex: "6BA377"),
            isFocused: true,
            onDelete: {},
            onToggle: {}
        )
    }
    .padding()
    .background(Color(hex: "D4EDDA"))
    .modelContainer(container)
}
