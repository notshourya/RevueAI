import SwiftUI
import SwiftData

/// A floating glass month calendar at the bottom of the sidebar, styled to
/// match the review cards. Days with captured notes show a dot; clicking a
/// day (or the month title) opens the full calendar surface.
struct MiniCalendarView: View {
    var model: CalendarPaneModel
    /// Opens the full calendar surface with this day selected.
    var onOpenDay: (Date) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @State private var authRefresh = 0

    private static let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    /// Same adaptive glass as the review cards.
    private var glassTint: Color {
        colorScheme == .dark ? .black.opacity(0.33) : .white.opacity(0.35)
    }

    var body: some View {
        Group {
            switch model.calendarProvider.authorization {
            case .authorized: calendarBody
            case .notDetermined, .denied: permissionRow
            }
        }
        .glassEffect(.clear.tint(glassTint), in: Self.shape)
        .id(authRefresh)
    }

    private var calendarBody: some View {
        VStack(spacing: 8) {
            header
            grid
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onAppear { CapturePlanner.prune(now: .now, in: context) }
    }

    private var header: some View {
        HStack {
            Button { withAnimation(.smooth) { model.stepMonth(by: -1) } } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .help("Previous month")
            Spacer()
            Button {
                onOpenDay(model.selectedDay)
            } label: {
                Text(model.monthTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .help("Open the calendar")
            Spacer()
            Button { withAnimation(.smooth) { model.stepMonth(by: 1) } } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .help("Next month")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var grid: some View {
        let dotDays = model.daysWithNotes(in: context)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Calendar.current.veryShortWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            ForEach(Array(model.monthDays().enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day, hasNotes: dotDays.contains(Calendar.current.component(.day, from: day)))
                } else {
                    Color.clear.frame(height: 24)
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
                    .font(.system(size: 11, weight: isToday ? .bold : .medium))
                    .frame(width: 21, height: 18)
                    .background(
                        Circle().fill(isToday ? Color.red.opacity(0.85)
                                      : isSelected ? Color.accentColor.opacity(0.35) : .clear)
                    )
                    .foregroundStyle(isToday ? .white : .primary)
                Circle()
                    .fill(hasNotes ? Color.accentColor : .clear)
                    .frame(width: 3.5, height: 3.5)
            }
            .frame(maxWidth: .infinity, minHeight: 24)
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
        .padding(14)
        .help("RevueAI shows your meetings so captures can be planned and titled. Events are never modified.")
    }
}
