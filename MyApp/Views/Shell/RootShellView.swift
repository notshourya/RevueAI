import SwiftUI
import SwiftData

/// The main window: the reviews sidebar with an Apple-Calendar-style mini
/// month calendar pinned at its bottom, the reading pane as detail, and the
/// live-capture panel as a toggleable inspector that opens itself when
/// capture starts. Toolbar switchers collapse the calendar and flip between
/// active and archived reviews.
struct RootShellView: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @State private var selection: ReviewNote?
    @State private var showLive = false
    @State private var showArchived = false
    @AppStorage("showMiniCalendar") private var showMiniCalendar = true
    @State private var calendarModel = CalendarPaneModel(calendar: CalendarService())
    @AppStorage("floatingOrbEnabled") private var floatingOrbEnabled = true
    @State private var floatingOrb = FloatingOrbController()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var notifier = ArmedMeetingNotifier()
    @State private var duePrompt: PlannedCapture?

    var body: some View {
        NavigationSplitView {
            LibraryPane(selection: $selection,
                        showArchived: showArchived,
                        showMiniCalendar: showMiniCalendar,
                        calendarModel: calendarModel,
                        onArmChanged: {
                            Task {
                                await notifier.ensureAuthorization()
                                notifier.sync(with: context)
                            }
                        })
                .navigationSplitViewColumnWidth(min: 270, ideal: 320)
        } detail: {
            readerContent
        }
        .inspector(isPresented: $showLive) {
            LivePanelView()
                .inspectorColumnWidth(min: 260, ideal: 300)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Toggle(isOn: $showMiniCalendar.animation(.smooth)) {
                    Label("Calendar", systemImage: "calendar")
                }
                .toggleStyle(.button)
                .help(showMiniCalendar ? "Hide the calendar" : "Show the calendar")
                Toggle(isOn: Binding(
                    get: { showArchived },
                    set: { value in withAnimation(.smooth) { showArchived = value } }
                )) {
                    Label("Archived", systemImage: "archivebox")
                }
                .toggleStyle(.button)
                .help(showArchived ? "Show active reviews" : "Show archived reviews")
            }
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
                .tint(Theme.accent)
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
            .glassEffect(.regular.tint(Theme.panel.opacity(0.28)), in: .rect(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.panelStroke, lineWidth: 1)
            )
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
                    OrbView(state: .idle, size: 58)
                    Text("Select a review")
                        .font(Theme.display(20))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
