import SwiftUI
import SwiftData
import AppKit

private extension NSView {
    /// Depth-first search for a subview of the given type.
    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let nested = subview.firstSubview(of: type) { return nested }
        }
        return nil
    }
}

/// The main window: the reviews sidebar with an Apple-Calendar-style mini
/// month calendar pinned at its bottom, the reading pane as detail, and the
/// live-capture panel as a toggleable inspector that opens itself when
/// capture starts. Toolbar switchers collapse the calendar and flip between
/// active and archived reviews.
struct RootShellView: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @State private var selection: ReviewNote?
    @State private var showCalendarSurface = false
    @State private var calendarModel = CalendarPaneModel(calendar: CalendarService())
    @AppStorage("floatingOrbEnabled") private var floatingOrbEnabled = true
    @State private var floatingOrb = FloatingOrbController()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var notifier = ArmedMeetingNotifier()
    @State private var duePrompt: PlannedCapture?
    @State private var showAssistant = false
    @State private var assistantQuery = ""
    @State private var assistant = ReviewAssistant(container: SharedModel.container)

    private static let assistantSuggestions = [
        "Which action items are still open?",
        "What did we decide recently?",
        "Summarize last week's reviews",
    ]

    var body: some View {
        NavigationSplitView {
            LibraryPane(selection: $selection,
                        calendarModel: calendarModel,
                        onOpenCalendar: { day in
                            calendarModel.selectedDay = day
                            withAnimation(.smooth) { showCalendarSurface = true }
                        })
                .navigationSplitViewColumnWidth(min: 270, ideal: 320)
        } detail: {
            readerContent
        }
        .searchable(text: $assistantQuery, placement: .toolbar, prompt: "Ask about your reviews…")
        .background(ToolbarSearchCenterer())
        .onSubmit(of: .search) {
            let text = assistantQuery
            assistantQuery = ""
            submitAssistantQuery(text)
        }
        .overlay(alignment: .top) {
            if showAssistant {
                AssistantResultsCard(assistant: assistant,
                                     suggestions: Self.assistantSuggestions,
                                     showsField: false,
                                     onAsk: { submitAssistantQuery($0) },
                                     onOpenNote: { noteID in
                                         withAnimation(.smooth) { showAssistant = false }
                                         openNote(id: noteID)
                                     },
                                     onClose: {
                                         withAnimation(.smooth) { showAssistant = false }
                                     })
            }
        }
        .onChange(of: coordinator.state) { _, newValue in
            floatingOrb.update(state: newValue, enabled: floatingOrbEnabled, coordinator: coordinator)
        }
        .onChange(of: selection) { _, newValue in
            if newValue != nil {
                withAnimation(.smooth) { showCalendarSurface = false }
            }
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

    private func submitAssistantQuery(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(.smooth) { showAssistant = true }
        Task { await assistant.ask(trimmed) }
    }

    private func openNote(id: UUID) {
        var descriptor = FetchDescriptor<ReviewNote>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let note = try? context.fetch(descriptor).first else { return }
        withAnimation(.smooth) {
            showCalendarSurface = false
            selection = note
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
        readerBody
            .background {
                SearchActivationBridge { active in
                    if active { withAnimation(.smooth) { showAssistant = true } }
                }
            }
    }

    /// AppKit escape hatch: SwiftUI toolbars on this OS can't center items,
    /// but AppKit can — Safari and Music center their fields via
    /// `NSToolbar.centeredItemIdentifiers`. This probe finds the window's
    /// toolbar, locates the bridged search item, and centers it. Retries
    /// briefly because SwiftUI populates the toolbar asynchronously.
    private struct ToolbarSearchCenterer: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            for delay in [0.1, 0.6, 1.5, 3.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view] in
                    guard let view else { return }
                    Self.centerSearchItem(in: view.window)
                }
            }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            DispatchQueue.main.async { [weak nsView] in
                Self.centerSearchItem(in: nsView?.window)
            }
        }

        static func centerSearchItem(in window: NSWindow?) {
            guard let toolbar = window?.toolbar else { return }
            // Drop the sidebar tracking separators: they split the toolbar
            // into sections and "centered" becomes section-centered. One
            // section means the field centers on the window, sidebar
            // visible or not.
            for (index, item) in toolbar.items.enumerated().reversed()
            where item is NSTrackingSeparatorToolbarItem {
                toolbar.removeItem(at: index)
            }
            let searchItem = toolbar.items.first {
                $0 is NSSearchToolbarItem || $0.view?.firstSubview(of: NSSearchField.self) != nil
            }
            guard let identifier = searchItem?.itemIdentifier,
                  toolbar.centeredItemIdentifiers != [identifier] else { return }
            toolbar.centeredItemIdentifiers = [identifier]
        }
    }

    /// Zero-size probe that reports when the toolbar search field activates
    /// (`isSearching` is only readable from inside the searchable container).
    private struct SearchActivationBridge: View {
        @Environment(\.isSearching) private var isSearching
        var onChange: (Bool) -> Void

        var body: some View {
            Color.clear
                .frame(width: 0, height: 0)
                .onChange(of: isSearching) { _, active in onChange(active) }
        }
    }

    @ViewBuilder
    private var readerBody: some View {
        if showCalendarSurface {
            CalendarSurfaceView(model: calendarModel,
                                onOpenNote: { note in
                                    withAnimation(.smooth) {
                                        showCalendarSurface = false
                                        selection = note
                                    }
                                },
                                onArmChanged: {
                                    Task {
                                        await notifier.ensureAuthorization()
                                        notifier.sync(with: context)
                                    }
                                },
                                onClose: {
                                    withAnimation(.smooth) { showCalendarSurface = false }
                                })
        } else if let selection {
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
