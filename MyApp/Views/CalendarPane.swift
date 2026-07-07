import SwiftUI
import SwiftData

/// The calendar surface: month grid over the selected day's agenda. Rows
/// join meetings to their captured notes and carry the arm toggle.
struct CalendarPane: View {
    var model: CalendarPaneModel
    /// Jumps to a captured note in the Reviews section.
    var onOpenNote: (ReviewNote) -> Void
    var onArmChanged: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var refreshToken = 0

    var body: some View {
        Group {
            switch model.calendarProvider.authorization {
            case .authorized: content
            case .notDetermined, .denied: permissionState
            }
        }
        .navigationTitle("Calendar")
        .onAppear { CapturePlanner.prune(now: .now, in: context) }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            monthHeader
            monthGrid
            Divider()
            agendaList
        }
    }

    private var monthHeader: some View {
        HStack {
            Text(model.monthTitle).font(.headline)
            Spacer()
            Button { model.stepMonth(by: -1) } label: { Image(systemName: "chevron.left") }
            Button { model.selectedDay = .now; model.displayedMonth = .now } label: { Text("Today") }
            Button { model.stepMonth(by: 1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var monthGrid: some View {
        let dotDays = model.daysWithNotes(in: context)
        let columns = Array(repeating: GridItem(.flexible()), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Calendar.current.veryShortWeekdaySymbols, id: \.self) { symbol in
                Text(symbol).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(Array(model.monthDays().enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day, hasNotes: dotDays.contains(Calendar.current.component(.day, from: day)))
                } else {
                    Color.clear.frame(height: 28)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func dayCell(_ day: Date, hasNotes: Bool) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: model.selectedDay)
        let isToday = Calendar.current.isDateInToday(day)
        return Button {
            model.selectedDay = day
        } label: {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.callout.weight(isToday ? .bold : .regular))
                Circle()
                    .fill(hasNotes ? Theme.accent : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.25) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Agenda

    private var agendaList: some View {
        let entries = model.agenda(in: context)
        return List {
            if entries.isEmpty {
                Text("No meetings on \(model.selectedDay.formatted(date: .abbreviated, time: .omitted)).")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                AgendaRow(entry: entry, refreshToken: $refreshToken,
                          onOpenNote: onOpenNote, onArmChanged: onArmChanged)
            }
        }
        .id(refreshToken)
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var permissionState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("Calendar access needed")
                .font(.headline)
            Text("RevueAI shows your meetings so captures can be planned and titled. Events are never modified.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button("Grant Access") {
                Task {
                    _ = await model.calendarProvider.requestAccess()
                    refreshToken += 1
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One meeting row: time, title, capture affordances.
private struct AgendaRow: View {
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
                Text(entry.event.title).font(.body.weight(.medium))
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
        .padding(.vertical, 2)
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
