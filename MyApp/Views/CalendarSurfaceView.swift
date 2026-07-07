import SwiftUI
import SwiftData

/// The full calendar surface shown in the detail area: a designed month view
/// with event pills inside day cells. Pills open the agenda popover (arm
/// toggle, note link, series history).
struct CalendarSurfaceView: View {
    var model: CalendarPaneModel
    var onOpenNote: (ReviewNote) -> Void
    var onArmChanged: () -> Void = {}
    var onClose: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var refreshToken = 0

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            header
            weekdayRow
            grid
        }
        .padding(16)
        .id(refreshToken)
        .background(AppBackground())
        .navigationTitle("Calendar")
        .onAppear { CapturePlanner.prune(now: .now, in: context) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(model.monthTitle)
                .font(.system(size: 24, weight: .bold))
            Spacer()
            Button { withAnimation(.smooth) { model.stepMonth(by: -1) } } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous month")
            Button("Today") {
                withAnimation(.smooth) {
                    model.displayedMonth = .now
                    model.selectedDay = .now
                }
            }
            Button { withAnimation(.smooth) { model.stepMonth(by: 1) } } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next month")
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help("Back to the review")
        }
        .buttonStyle(.bordered)
        .padding(.bottom, 12)
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(cal.shortWeekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Grid

    private var grid: some View {
        let byDay = model.monthAgenda(in: context)
        let dotDays = model.daysWithNotes(in: context)
        let cells = model.monthDays()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return GeometryReader { geo in
            let rowCount = max(1, cells.count / 7)
            let rowHeight = max(64, (geo.size.height - CGFloat(rowCount - 1) * 4) / CGFloat(rowCount))
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                        if let day {
                            DaySurfaceCell(
                                day: day,
                                entries: byDay[cal.component(.day, from: day)] ?? [],
                                hasNotes: dotDays.contains(cal.component(.day, from: day)),
                                isSelected: cal.isDate(day, inSameDayAs: model.selectedDay),
                                height: rowHeight,
                                onSelect: { model.selectedDay = day },
                                onOpenNote: onOpenNote,
                                onArmChanged: { refreshToken += 1; onArmChanged() }
                            )
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.quaternary.opacity(0.18))
                                .frame(height: rowHeight)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Day cell

private struct DaySurfaceCell: View {
    let day: Date
    let entries: [AgendaEntry]
    let hasNotes: Bool
    let isSelected: Bool
    let height: CGFloat
    var onSelect: () -> Void
    var onOpenNote: (ReviewNote) -> Void
    var onArmChanged: () -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var isWeekend: Bool { Calendar.current.isDateInWeekend(day) }
    private let maxPills = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.callout.weight(isToday ? .bold : .medium))
                    .foregroundStyle(isToday ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(isToday ? Color.red.opacity(0.85) : .clear))
                if hasNotes {
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                }
                Spacer()
            }
            ForEach(entries.prefix(maxPills)) { entry in
                EventPill(entry: entry, onOpenNote: onOpenNote, onArmChanged: onArmChanged)
            }
            if entries.count > maxPills {
                Text("+\(entries.count - maxPills) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.14)
                      : isWeekend ? Color.primary.opacity(0.025)
                      : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Event pill

private struct EventPill: View {
    let entry: AgendaEntry
    var onOpenNote: (ReviewNote) -> Void
    var onArmChanged: () -> Void

    @Environment(\.modelContext) private var context
    @State private var showDetail = false

    private var isArmed: Bool { CapturePlanner.isArmed(entry.event, in: context) }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 4) {
                if entry.note != nil {
                    Image(systemName: "doc.text.fill").font(.system(size: 8))
                } else if isArmed {
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                }
                Text(entry.event.start.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary)
                Text(entry.event.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(entry.note != nil ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDetail, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                AgendaEntryRow(entry: entry,
                               onOpenNote: { note in
                                   showDetail = false
                                   onOpenNote(note)
                               },
                               onArmChanged: onArmChanged)
            }
            .padding(12)
            .frame(width: 300)
        }
    }
}

// MARK: - Agenda row (shared with any agenda listing)

/// One meeting row: time, title, capture affordances.
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
