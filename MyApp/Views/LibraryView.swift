import SwiftUI
import SwiftData

enum LibraryLayout: String { case list, grid }

/// The reviews library — a sidebar of reviews (switchable between List and
/// Grid) plus a reading pane. List rows swipe to Archive/Delete; grid cards use
/// a long-press/right-click menu. Record is docked at the bottom of the sidebar.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(CaptureCoordinator.self) private var coordinator
    @Query(sort: \ReviewNote.date, order: .reverse) private var notes: [ReviewNote]

    @AppStorage("libraryLayout") private var layoutRaw = LibraryLayout.list.rawValue
    @State private var showArchived = false
    @State private var selection: ReviewNote?

    private var layout: LibraryLayout { LibraryLayout(rawValue: layoutRaw) ?? .list }
    private var shownNotes: [ReviewNote] { notes.filter { $0.isArchived == showArchived } }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
                .toolbar { sidebarToolbar }
        } detail: {
            detail
        }
        .onChange(of: shownNotes.count) {
            if selection == nil || !shownNotes.contains(where: { $0 == selection }) {
                selection = shownNotes.first
            }
        }
        .onChange(of: coordinator.state) { _, newValue in
            if newValue == .idle { selection = shownNotes.first }
        }
        .onChange(of: showArchived) { selection = shownNotes.first }
        .onAppear { selection = selection ?? shownNotes.first }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ZStack {
            PremiumBackground()
            Group {
                if shownNotes.isEmpty { emptyState }
                else {
                    switch layout {
                    case .list: listView
                    case .grid: gridView
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { recordBar }
    }

    private var listView: some View {
        List(selection: $selection) {
            Section {
                ForEach(shownNotes) { note in
                    NoteRow(note: note)
                        .tag(note)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init(top: 5, leading: 12, bottom: 5, trailing: 12))
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
            } header: {
                Text(showArchived ? "Archived" : "Reviews")
                    .font(Theme.display(26))
                    .textCase(nil)
                    .foregroundStyle(.primary)
                    .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var gridView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(showArchived ? "Archived" : "Reviews")
                    .font(Theme.display(26))
                    .padding(.horizontal, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: .infinity), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(shownNotes) { note in
                        NoteCard(note: note, isSelected: selection == note)
                            .onTapGesture { selection = note }
                            .contextMenu { rowMenu(note) }
                    }
                }
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
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

    // MARK: - Record dock

    private var recordBar: some View {
        VStack(spacing: 10) {
            if coordinator.isActive {
                HStack(spacing: 10) {
                    StateOrb(mode: coordinator.state == .processing ? .processing : .listening, size: 28)
                        .opacity(coordinator.state == .paused ? 0.4 : 1)
                    Text(coordinator.state == .paused ? "Paused · \(coordinator.elapsedText)" : "\(coordinator.elapsedText) · \(coordinator.capturedPhraseCount)")
                        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            Button(action: toggleCapture) {
                HStack(spacing: 8) {
                    Image(systemName: coordinator.isActive ? "stop.fill" : "record.circle.fill")
                    Text(coordinator.isActive ? "Stop & Summarize" : "Record")
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    (coordinator.isActive ? Color(red: 1, green: 0.4, blue: 0.43) : Color.accentColor).gradient,
                    in: Capsule()
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(coordinator.state == .processing)
            .opacity(coordinator.state == .processing ? 0.6 : 1)
        }
        .padding(14)
        .background(.ultraThinMaterial)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selection {
            NoteDetailView(note: selection)
        } else {
            ZStack {
                PremiumBackground()
                VStack(spacing: 14) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Select a review")
                        .font(Theme.display(24))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: showArchived ? "archivebox" : "waveform")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(showArchived ? "No archived reviews" : "No reviews yet")
                .font(Theme.display(20))
            if !showArchived {
                Text("Press Record below to capture your first review.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Picker("Layout", selection: $layoutRaw) {
                Image(systemName: "list.bullet").tag(LibraryLayout.list.rawValue)
                Image(systemName: "square.grid.2x2").tag(LibraryLayout.grid.rawValue)
            }
            .pickerStyle(.segmented)
            .help("Switch between list and grid")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                withAnimation(.smooth) { showArchived.toggle() }
            } label: {
                Label("Archived", systemImage: showArchived ? "archivebox.fill" : "archivebox")
            }
            .help(showArchived ? "Show active reviews" : "Show archived reviews")
        }
    }

    // MARK: - Actions

    private func toggleCapture() {
        Task {
            if coordinator.isActive { await coordinator.stop() }
            else { await coordinator.start(context: context) }
        }
    }

    private func archive(_ note: ReviewNote) {
        withAnimation(.smooth) { note.isArchived.toggle() }
        try? context.save()
    }

    private func delete(_ note: ReviewNote) {
        withAnimation(.smooth) { context.delete(note) }
        try? context.save()
    }
}

// MARK: - List row

private struct NoteRow: View {
    let note: ReviewNote

    private var itemCount: Int { note.actionItems?.count ?? 0 }
    private var openCount: Int { (note.openQuestions ?? []).filter { !$0.isResolved }.count }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(note.verdict.tint)
                .frame(width: 5, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text(note.title)
                    .font(Theme.display(16, .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    VerdictBadge(verdict: note.verdict)
                    if itemCount > 0 { Label("\(itemCount)", systemImage: "checklist") }
                    if openCount > 0 { Label("\(openCount)", systemImage: "questionmark.circle") }
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }
}

// MARK: - Grid card

private struct NoteCard: View {
    let note: ReviewNote
    var isSelected = false

    private var itemCount: Int { note.actionItems?.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { VerdictBadge(verdict: note.verdict); Spacer() }
            Text(note.title)
                .font(Theme.display(15, .semibold))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                if itemCount > 0 { Label("\(itemCount)", systemImage: "checklist") }
                Spacer()
                Text(note.date, format: .relative(presentation: .named))
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(height: 128, alignment: .topLeading)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Theme.cardStroke, lineWidth: isSelected ? 2 : 1)
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2)
                .fill(note.verdict.tint.opacity(0.85))
                .frame(height: 3)
                .padding(.horizontal, 14)
        }
        .contentShape(Rectangle())
    }
}
