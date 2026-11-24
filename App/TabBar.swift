import QuatermCore
import SwiftUI

struct TabItem: Identifiable, Equatable {
    let id: UUID
    var title: String
}

@MainActor
final class TabStore: ObservableObject {
    @Published var tabs: [TabItem] = []
    @Published var selectedID: UUID?
    @Published var isPinned = false

    var onSelect: (UUID) -> Void = { _ in }
    var onClose: (UUID) -> Void = { _ in }
    var onNewTab: () -> Void = {}
    var onTogglePin: () -> Void = {}
}

struct TabBar: View {
    @ObservedObject var store: TabStore

    var body: some View {
        HStack(spacing: 2) {
            ForEach(store.tabs) { tab in
                TabButton(
                    title: tab.title,
                    isSelected: tab.id == store.selectedID,
                    onSelect: { store.onSelect(tab.id) },
                    onClose: { store.onClose(tab.id) }
                )
            }
            Button(action: store.onNewTab) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            Spacer()
            Button(action: store.onTogglePin) {
                Image(systemName: store.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .help(store.isPinned ? Messages.pinned : Messages.unpinned)
        }
        .padding(.horizontal, 8)
        .frame(height: Constants.tabBarHeight)
        .background(.bar)
    }
}

private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .help(Messages.closeTab)
            // Hidden but still laid out, so the tab does not change width on hover.
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? Color.primary.opacity(0.15) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
}
