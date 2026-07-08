import SwiftUI
import SwiftData

/// One meeting row: time, title, capture affordances. Used by the day
/// agenda popover.
struct AgendaEntryRow: View {
    let entry: AgendaEntry
    var onOpenNote: (ReviewNote) -> Void
    var onArmChanged: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var showHistory = false

    private var isUpcoming: Bool { entry.event.start > .now }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.event.title).font(.callout.weight(.medium))
                HStack(spacing: 6) {
                    Text(entry.event.start.formatted(date: .omitted, time: .shortened))
                    if !entry.event.attendees.isEmpty {
                        Label("\(entry.event.attendees.count)", systemImage: "person.2")
                    }
                    if entry.event.isRecurring, entry.seriesNoteCount > 0 {
                        Button {
                            showHistory = true
                        } label: {
                            Label("\(entry.seriesNoteCount) notes", systemImage: "doc.text")
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showHistory, arrowEdge: .trailing) {
                            seriesHistory
                        }
                        .help("Capture history for this series")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let note = entry.note {
                Button {
                    onOpenNote(note)
                } label: {
                    Label("Note", systemImage: "doc.text.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .help("Open the captured note")
            } else if isUpcoming {
                Toggle("Arm", isOn: Binding(
                    get: { CapturePlanner.isArmed(entry.event, in: context) },
                    set: { armed in
                        if armed { CapturePlanner.arm(entry.event, in: context) }
                        else { CapturePlanner.disarm(entry.event, in: context) }
                        onArmChanged()
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Prompt to start listening when this meeting begins")
            }
        }
    }

    /// Series capture history: every note snapshotted from this series.
    private var seriesHistory: some View {
        let seriesID = entry.event.seriesID
        let descriptor = FetchDescriptor<MeetingSnapshot>(
            predicate: #Predicate { $0.seriesID == seriesID },
            sortBy: [SortDescriptor(\.occurrenceDate, order: .reverse)]
        )
        let snapshots = ((try? context.fetch(descriptor)) ?? []).filter { $0.note != nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Captured from this series")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(snapshots) { snapshot in
                if let note = snapshot.note {
                    Button {
                        showHistory = false
                        onOpenNote(note)
                    } label: {
                        HStack {
                            Text(snapshot.occurrenceDate.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Image(systemName: "arrow.right").font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 220)
    }
}
