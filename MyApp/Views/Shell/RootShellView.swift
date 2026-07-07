import SwiftUI
import SwiftData

/// The main window: three parallel glass panels (Library | Reader | Live) on
/// the dark backdrop, resizable and collapsible. The live panel auto-expands
/// when capture starts.
struct RootShellView: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @State private var layout = PanelLayoutModel()
    @State private var selection: ReviewNote?
    @AppStorage("floatingOrbEnabled") private var floatingOrbEnabled = true
    @State private var floatingOrb = FloatingOrbController()

    var body: some View {
        ZStack {
            PremiumBackground()
            PanelSplitView(model: layout) { panel in
                switch panel {
                case .library:
                    PanelChrome(title: "Library", systemImage: "books.vertical",
                                onCollapse: { layout.toggleCollapse(.library) },
                                accessory: {}) {
                        LibraryPane(selection: $selection)
                    }
                case .reader:
                    PanelChrome(title: "Review", systemImage: "doc.text",
                                onCollapse: { layout.toggleCollapse(.reader) },
                                accessory: {}) {
                        readerContent
                    }
                case .live:
                    PanelChrome(title: "Live", systemImage: "waveform",
                                onCollapse: { layout.toggleCollapse(.live) },
                                accessory: {}) {
                        LivePanelView()
                    }
                }
            }
            .padding(12)
        }
        .onChange(of: coordinator.state) { _, newValue in
            if newValue == .listening {
                withAnimation(.smooth) { layout.expandLive() }
            }
            floatingOrb.update(state: newValue, enabled: floatingOrbEnabled, coordinator: coordinator)
        }
        .onChange(of: floatingOrbEnabled) { _, enabled in
            floatingOrb.update(state: coordinator.state, enabled: enabled, coordinator: coordinator)
        }
    }

    @ViewBuilder
    private var readerContent: some View {
        if let selection {
            NoteDetailView(note: selection)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Select a review")
                    .font(Theme.display(20))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
