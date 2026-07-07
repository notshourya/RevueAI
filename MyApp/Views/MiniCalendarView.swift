import SwiftUI
import SwiftData

/// Apple-Calendar-style mini month calendar pinned at the bottom of the
/// sidebar. Days with captured notes show a dot; clicking a day pops that
/// day's agenda (arm toggles, note links, series history).
struct MiniCalendarView: View {
    var model: CalendarPaneModel
    var onOpenNote: (ReviewNote) -> Void
    var onArmChanged: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var authRefresh = 0

    var body: some View {
        Group {
            switch model.calendarProvider.authorization {
            case .authorized: calendarBody
            case .notDetermined, .denied: permissionRow
            }
        }
        .id(authRefresh)
    }

    private var calendarBody: some View {
        VStack(spacing: 6) {
            header
            grid
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .onAppear { CapturePlanner.prune(now: .now, in: context) }
    }

    private var header: some View {
        HStack {
            Button { model.stepMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                .help("Previous month")
            Spacer()
            Button {
                model.displayedMonth = .now
                model.selectedDay = .now
            } label: {
                Text(model.monthTitle).font(.system(size: 12, weight: .semibold))
            }
            .help("Back to today")
            Spacer()
            Button { model.stepMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                .help("Next month")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var grid: some View {
        let dotDays = model.daysWithNotes(in: context)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Calendar.current.veryShortWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            ForEach(Array(model.monthDays().enumerated()), id: \.offset) { _, day in
                if let day {
                    MiniDayCell(day: day,
                                hasNotes: dotDays.contains(Calendar.current.component(.day, from: day)),
                                model: model,
                                onOpenNote: onOpenNote,
                                onArmChanged: onArmChanged)
                } else {
                    Color.clear.frame(height: 22)
                }
            }
        }
    }

    private var permissionRow: some View {
        Button {
            Task {
                _ = await model.calendarProvider.requestAccess()
                authRefresh += 1
            }
        } label: {
            Label("Show meetings — grant calendar access", systemImage: "calendar.badge.exclamationmark")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(10)
        .help("RevueAI shows your meetings so captures can be planned and titled. Events are never modified.")
    }
}

// MARK: - Day cell

private struct MiniDayCell: View {
    let day: Date
    let hasNotes: Bool
    var model: CalendarPaneModel
    var onOpenNote: (ReviewNote) -> Void
    var onArmChanged: () -> Void

    @State private var showAgenda = false

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        Button {
            model.selectedDay = day
            showAgenda = true
        } label: {
            VStack(spacing: 1) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.system(size: 10, weight: isToday ? .bold : .regular))
                    .frame(width: 18, height: 16)
                    .background(Circle().fill(isToday ? Color.red.opacity(0.85) : .clear))
                    .foregroundStyle(isToday ? .white : .primary)
                Circle()
                    .fill(hasNotes ? Theme.accent : .clear)
                    .frame(width: 3, height: 3)
            }
            .frame(maxWidth: .infinity, minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showAgenda, arrowEdge: .trailing) {
            DayAgendaPopover(day: day, model: model,
                             onOpenNote: { note in
                                 showAgenda = false
                                 onOpenNote(note)
                             },
                             onArmChanged: onArmChanged)
        }
    }
}

// MARK: - Day agenda popover

/// The selected day's meetings: arm toggles for upcoming ones, note links
/// for captured ones, series history for recurring ones.
struct DayAgendaPopover: View {
    let day: Date
    var model: CalendarPaneModel
    var onOpenNote: (ReviewNote) -> Void
    var onArmChanged: () -> Void

    @Environment(\.modelContext) private var context
    @State private var refreshToken = 0

    var body: some View {
        let entries = model.agenda(in: context)
        VStack(alignment: .leading, spacing: 8) {
            Text(day.formatted(date: .complete, time: .omitted))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if entries.isEmpty {
                Text("No meetings.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ForEach(entries) { entry in
                AgendaEntryRow(entry: entry, refreshToken: $refreshToken,
                               onOpenNote: onOpenNote, onArmChanged: onArmChanged)
            }
        }
        .id(refreshToken)
        .padding(12)
        .frame(width: 300)
    }
}

/// One meeting row: time, title, capture affordances.
private struct AgendaEntryRow: View {
    let entry: AgendaEntry
    @Binding var refreshToken: Int
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
                        refreshToken += 1
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
