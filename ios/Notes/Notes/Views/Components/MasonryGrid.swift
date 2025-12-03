import SwiftUI

struct MasonryGrid<Data, Content>: View where Data: RandomAccessCollection, Data.Element: Identifiable, Content: View {
    let data: Data
    let columns: Int
    let spacing: CGFloat
    let content: (Data.Element) -> Content

    init(
        data: Data,
        columns: Int = 2,
        spacing: CGFloat = 12,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.columns = columns
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { columnIndex in
                LazyVStack(spacing: spacing) {
                    ForEach(itemsForColumn(columnIndex)) { item in
                        content(item)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Distributes items round-robin across columns
    private func itemsForColumn(_ column: Int) -> [Data.Element] {
        let array = Array(data)
        return array.enumerated()
            .filter { $0.offset % columns == column }
            .map { $0.element }
    }
}

#Preview {
    ScrollView {
        MasonryGrid(
            data: [
                PreviewNote(id: "1", title: "Short note"),
                PreviewNote(id: "2", title: "Medium note", content: "This is a medium length note with some content."),
                PreviewNote(id: "3", title: "Long note", content: "This is a longer note with quite a bit more content that should make the card taller than the others."),
                PreviewNote(id: "4", title: "Another short one"),
                PreviewNote(id: "5", title: "Fifth note", content: "Some content here too"),
            ],
            columns: 2,
            spacing: 12
        ) { note in
            VStack(alignment: .leading, spacing: 8) {
                Text(note.title)
                    .font(.headline)
                if let content = note.content {
                    Text(content)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(radius: 2)
        }
        .padding()
    }
    .background(Color.gray.opacity(0.1))
}

// Preview helper
private struct PreviewNote: Identifiable {
    let id: String
    let title: String
    var content: String? = nil
}
