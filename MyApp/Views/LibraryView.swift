import SwiftUI
import SwiftData

/// The reviews sidebar — a native scrollable list with standard selection,
/// swipe actions, and the record dock at the bottom. Selection is owned by
/// the shell.
struct LibraryPane: View {
    @Environment(\.modelContext) private var context
    @Environment(CaptureCoordinator.self) private var coordinator
    @Query(sort: \ReviewNote.date, order: .reverse) private var notes: [ReviewNote]

    @Binding var selection: ReviewNote?
    var calendarModel: CalendarPaneModel
    var onOpenCalendar: (Date) -> Void = { _ in }

    @State private var showArchived = false

    private var shownNotes: [ReviewNote] { notes.filter { $0.isArchived == showArchived } }

    var body: some View {
        List(selection: $selection) {
            ForEach(shownNotes) { note in
                NoteRow(note: note)
                    .tag(note)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { delete(note) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { archive(note) } label: {
                            Label(note.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                        }
                        .tint(.orange)
                    }
                    .contextMenu { rowMenu(note) }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(showArchived ? "Archived" : "Reviews")
        .overlay {
            if shownNotes.isEmpty { emptyState }
        }
        .safeAreaInset(edge: .bottom) { bottomDock }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Toggle(isOn: Binding(
                    get: { showArchived },
                    set: { value in withAnimation(.smooth) { showArchived = value } }
                )) {
                    Label("Archived", systemImage: "archivebox")
                }
                .toggleStyle(.button)
                .help(showArchived ? "Show active reviews" : "Show archived reviews")
            }
        }
        .onChange(of: showArchived) { selection = shownNotes.first }
        .onChange(of: shownNotes.count) {
            if selection == nil || !shownNotes.contains(where: { $0 == selection }) {
                selection = shownNotes.first
            }
        }
        .onChange(of: coordinator.state) { _, newValue in
            if newValue == .idle { selection = shownNotes.first }
        }
        .onAppear {
            if selection == nil || !shownNotes.contains(where: { $0 == selection }) {
                selection = shownNotes.first
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ note: ReviewNote) -> some View {
        Button { archive(note) } label: {
            Label(note.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
        }
        Button(role: .destructive) { delete(note) } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Bottom dock (mini calendar, always present)

    private var bottomDock: some View {
        VStack(spacing: 0) {
            Divider()
            MiniCalendarView(model: calendarModel, onOpenDay: onOpenCalendar)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: showArchived ? "archivebox" : "waveform")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(showArchived ? "No archived reviews" : "No reviews yet")
                .font(.headline)
            if !showArchived {
                Text("Start a capture from the menu bar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
    }

    // MARK: - Actions

    private func archive(_ note: ReviewNote) {
        withAnimation(.smooth) { note.isArchived.toggle() }
        try? context.save()
    }

    private func delete(_ note: ReviewNote) {
        withAnimation(.smooth) { context.delete(note) }
        try? context.save()
    }
}

// MARK: - Sidebar row

private struct NoteRow: View {
    let note: ReviewNote

    private var itemCount: Int { note.actionItems?.count ?? 0 }
    private var openCount: Int { (note.openQuestions ?? []).filter { !$0.isResolved }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title)
                .font(.body.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 6) {
                Image(systemName: note.verdict.systemImage)
                    .foregroundStyle(note.verdict.tint)
                Text(note.date, format: .relative(presentation: .named))
                if itemCount > 0 { Label("\(itemCount)", systemImage: "checklist") }
                if openCount > 0 { Label("\(openCount)", systemImage: "questionmark.circle") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
