import SwiftUI
import SwiftData

/// The main window: a native sidebar of reviews, the reading pane as detail,
/// and the live-capture panel as a toggleable inspector that opens itself
/// when capture starts.
struct RootShellView: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @State private var selection: ReviewNote?
    @State private var showLive = false
    @AppStorage("floatingOrbEnabled") private var floatingOrbEnabled = true
    @State private var floatingOrb = FloatingOrbController()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            LibraryPane(selection: $selection)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
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
