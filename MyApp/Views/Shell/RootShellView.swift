import SwiftUI
import SwiftData

enum LibrarySection: String, CaseIterable, Identifiable {
    case reviews, archived, calendar

    var id: String { rawValue }
    var label: String {
        switch self {
        case .reviews: "Reviews"
        case .archived: "Archived"
        case .calendar: "Calendar"
        }
    }
    var systemImage: String {
        switch self {
        case .reviews: "doc.text"
        case .archived: "archivebox"
        case .calendar: "calendar"
        }
    }
}

/// The main window: a source-list sidebar (Reviews / Archived / Calendar),
/// the section's content list in the middle, the reading pane as detail,
/// and the live-capture panel as a toggleable inspector that opens itself
/// when capture starts.
struct RootShellView: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @State private var selection: ReviewNote?
    @State private var showLive = false
    @State private var section: LibrarySection = .reviews
    @State private var calendarModel = CalendarPaneModel(calendar: CalendarService())
    @AppStorage("floatingOrbEnabled") private var floatingOrbEnabled = true
    @State private var floatingOrb = FloatingOrbController()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var notifier = ArmedMeetingNotifier()
    @State private var duePrompt: PlannedCapture?

    var body: some View {
        NavigationSplitView {
            List(LibrarySection.allCases, selection: Binding(
                get: { Optional(section) },
                set: { if let value = $0 { section = value } }
            )) { item in
                Label(item.label, systemImage: item.systemImage).tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } content: {
            switch section {
            case .reviews:
                LibraryPane(selection: $selection, showArchived: false)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 320)
            case .archived:
                LibraryPane(selection: $selection, showArchived: true)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 320)
            case .calendar:
                CalendarPane(model: calendarModel, onOpenNote: { note in
                    section = .reviews
                    selection = note
                }, onArmChanged: {
                    Task {
                        await notifier.ensureAuthorization()
                        notifier.sync(with: context)
                    }
                })
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
            }
        } detail: {
            readerContent
        }
        .inspector(isPresented: $showLive) {
            LivePanelView()
                .inspectorColumnWidth(min: 260, ideal: 300)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showLive.toggle()
                } label: {
                    Label("Live", systemImage: "waveform")
                }
                .help(showLive ? "Hide the live capture panel" : "Show the live capture panel")
            }
        }
        .onChange(of: coordinator.state) { _, newValue in
            if newValue == .listening {
                withAnimation(.smooth) { showLive = true }
            }
            floatingOrb.update(state: newValue, enabled: floatingOrbEnabled, coordinator: coordinator)
        }
        .onChange(of: floatingOrbEnabled) { _, enabled in
            floatingOrb.update(state: coordinator.state, enabled: enabled, coordinator: coordinator)
        }
        .onAppear {
            if !hasCompletedOnboarding { showOnboarding = true }
        }
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if !completed { showOnboarding = true }
        }
        .sheet(isPresented: $showOnboarding, onDismiss: { hasCompletedOnboarding = true }) {
            OnboardingSheet(isPresented: $showOnboarding) {
                Task { await coordinator.start(context: context) }
            }
        }
        .overlay(alignment: .bottom) { promptCard }
        .task {
            notifier.activate(context: context)
            notifier.onStartRequested = { planned in
                startFromPlanned(planned)
            }
            notifier.sync(with: context)
            // Poll for due armed meetings so the in-app card works even when
            // notifications are denied. 30s granularity is plenty.
            while !Task.isCancelled {
                if coordinator.state == .idle {
                    duePrompt = CapturePlanner.duePrompt(now: .now, in: context)
                } else {
                    duePrompt = nil
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: - Armed-meeting prompt

    @ViewBuilder
    private var promptCard: some View {
        if let planned = duePrompt {
            HStack(spacing: 12) {
                OrbView(state: .idle, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(planned.title) started").font(Theme.rounded(13, .semibold))
                    Text("Start listening?").font(Theme.rounded(11)).foregroundStyle(.secondary)
                }
                Button("Start") {
                    let consumed = CapturePlanner.consumeMatch(eventID: planned.eventID,
                                                               occurrence: planned.occurrenceDate,
                                                               in: context)
                    startFromPlanned(consumed ?? planned)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    CapturePlanner.consumeMatch(eventID: planned.eventID,
                                                occurrence: planned.occurrenceDate, in: context)
                    duePrompt = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func startFromPlanned(_ planned: PlannedCapture) {
        duePrompt = nil
        let meeting = MeetingEvent(id: planned.eventID, seriesID: planned.seriesID,
                                   title: planned.title, start: planned.occurrenceDate,
                                   end: planned.occurrenceDate.addingTimeInterval(1800),
                                   attendees: [], isRecurring: false)
        Task { await coordinator.start(context: context, meeting: meeting) }
    }

    @ViewBuilder
    private var readerContent: some View {
        if let selection {
            NoteDetailView(note: selection)
        } else {
            ZStack {
                PremiumBackground()
                VStack(spacing: 14) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Select a review")
                        .font(Theme.display(20))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
