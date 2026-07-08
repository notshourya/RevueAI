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
    var onArmChanged: () -> Void = {}

    @State private var showArchived = false
    @State private var filterDay: Date?

    private var shownNotes: [ReviewNote] {
        notes.filter { note in
            guard note.isArchived == showArchived else { return false }
            if let filterDay {
                return Calendar.current.isDate(note.date, inSameDayAs: filterDay)
            }
            return true
        }
    }

    var body: some View {
        ScrollView {
            if let filterDay {
                filterChip(for: filterDay)
                    .padding(.top, 10)
            }
            // Siri-style sizing: columns grow with the sidebar but cap out,
            // so cards get proportionally larger instead of stretching.
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<2, id: \.self) { column in
                    LazyVStack(spacing: 12) {
                        ForEach(distributed(into: 2)[column]) { note in
                            ReviewCard(note: note, isSelected: selection == note)
                                .onTapGesture { selection = note }
                                .contextMenu { rowMenu(note) }
                        }
                    }
                    .frame(maxWidth: 250)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(12)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
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
        .onChange(of: filterDay) {
            if selection == nil || !shownNotes.contains(where: { $0 == selection }) {
                selection = shownNotes.first
            }
        }
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

    /// Greedy masonry: each review goes to the currently-shortest column so
    /// heights stay balanced and cards stagger like the Siri history grid.
    private func distributed(into columnCount: Int) -> [[ReviewNote]] {
        var columns = Array(repeating: [ReviewNote](), count: columnCount)
        var heights = Array(repeating: CGFloat(0), count: columnCount)
        for note in shownNotes {
            let target = heights.firstIndex(of: heights.min() ?? 0) ?? 0
            columns[target].append(note)
            heights[target] += estimatedHeight(note)
        }
        return columns
    }

    private func estimatedHeight(_ note: ReviewNote) -> CGFloat {
        let titleLines = min(3, max(1, note.title.count / 16 + 1))
        let bodyLines = note.summary.isEmpty ? 0 : min(4, note.summary.count / 20 + 1)
        return CGFloat(78 + titleLines * 19 + bodyLines * 15)
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

    // MARK: - Bottom dock (date ruler, always present)

    private var bottomDock: some View {
        DateRulerView(model: calendarModel,
                      filterDay: $filterDay,
                      onOpenNote: { selection = $0 },
                      onArmChanged: onArmChanged)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .padding(.top, 4)
            .background {
                // Progressive blur like the toolbar edge: cards fade out
                // under the ruler instead of bleeding through its glass.
                // The scrim uses the window background color so it deepens
                // in dark mode and lightens in light mode (no grey cast).
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(Theme.ink.opacity(0.72))
                }
                .mask(
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .black, location: 0.45),
                                           .init(color: .black, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .padding(.top, -28)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            }
    }

    /// Shown while the ruler filters the library to one past day.
    private func filterChip(for day: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
            Text("Showing \(day.formatted(date: .abbreviated, time: .omitted))")
            Button {
                withAnimation(.smooth) { filterDay = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Clear the date filter")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
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

// MARK: - Review card (Siri-history style)

/// A soft rounded card: timestamp caption, bold title, summary preview, and
/// a compact status row. Selection is a ring, like the Siri history grid.
private struct ReviewCard: View {
    let note: ReviewNote
    var isSelected = false

    @Environment(\.colorScheme) private var colorScheme

    /// Deepens the glass in dark mode, brightens it in light mode.
    private var glassTint: Color {
        colorScheme == .dark ? .black.opacity(0.33) : .white.opacity(0.35)
    }

    private var itemCount: Int { note.actionItems?.count ?? 0 }
    private var openCount: Int { (note.openQuestions ?? []).filter { !$0.isResolved }.count }
    private static let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.date, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(note.title.isEmpty ? "Untitled review" : note.title)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if !note.summary.isEmpty {
                Text(note.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Image(systemName: note.verdict.systemImage)
                    .foregroundStyle(note.verdict.tint)
                if itemCount > 0 { Label("\(itemCount)", systemImage: "checklist") }
                if openCount > 0 { Label("\(openCount)", systemImage: "questionmark.circle") }
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.clear.tint(glassTint), in: Self.shape)
        .overlay(Self.shape.strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Self.shape)
    }
}
