import SwiftUI
import SwiftData

/// Apple-Calendar-style mini month calendar pinned at the bottom of the
/// sidebar. Days with captured notes show a dot; clicking a day (or the
/// month title) opens the full calendar surface in the detail area.
struct MiniCalendarView: View {
    var model: CalendarPaneModel
    /// Opens the full calendar surface with this day selected.
    var onOpenDay: (Date) -> Void

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
                onOpenDay(model.selectedDay)
            } label: {
                Text(model.monthTitle).font(.system(size: 12, weight: .semibold))
            }
            .help("Open the calendar")
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
                    dayCell(day, hasNotes: dotDays.contains(Calendar.current.component(.day, from: day)))
                } else {
                    Color.clear.frame(height: 22)
                }
            }
        }
    }

    private func dayCell(_ day: Date, hasNotes: Bool) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let isSelected = Calendar.current.isDate(day, inSameDayAs: model.selectedDay)
        return Button {
            model.selectedDay = day
            onOpenDay(day)
        } label: {
            VStack(spacing: 1) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.system(size: 10, weight: isToday ? .bold : .regular))
                    .frame(width: 18, height: 16)
                    .background(
                        Circle().fill(isToday ? Color.red.opacity(0.85)
                                      : isSelected ? Color.accentColor.opacity(0.35) : .clear)
                    )
                    .foregroundStyle(isToday ? .white : .primary)
                Circle()
                    .fill(hasNotes ? Theme.accent : .clear)
                    .frame(width: 3, height: 3)
            }
            .frame(maxWidth: .infinity, minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
