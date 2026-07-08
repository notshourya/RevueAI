import SwiftUI
import SwiftData
import AppKit

/// A timer-style date scrubber in a glass widget: a massive date readout
/// over a fixed center pointer, with a tick ruler scrolling beneath it.
/// Haptics click as days pass. Clicking the date opens the day's agenda in
/// a popover; settling on a past day filters the library to that day.
struct DateRulerView: View {
    var model: CalendarPaneModel
    /// Set to a past day when the ruler settles there; nil on today/future.
    @Binding var filterDay: Date?
    var onOpenNote: (ReviewNote) -> Void
    var onArmChanged: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIndex: Int? = DateRulerView.todayIndex
    @State private var showAgenda = false

    private static let pastDays = 365
    private static let futureDays = 90
    private static var todayIndex: Int { pastDays }
    private static let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    /// Same adaptive glass as the review cards.
    private var glassTint: Color {
        colorScheme == .dark ? .black.opacity(0.33) : .white.opacity(0.35)
    }

    private var selectedDay: Date {
        Self.day(for: selectedIndex ?? Self.todayIndex)
    }

    private static func day(for index: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: index - pastDays,
                              to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    var body: some View {
        VStack(spacing: 6) {
            dateReadout
            ruler
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .glassEffect(.clear.tint(glassTint), in: Self.shape)
        .onAppear { CapturePlanner.prune(now: .now, in: context) }
        .onChange(of: selectedIndex) { oldValue, newValue in
            guard let newValue, oldValue != newValue else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            let day = Self.day(for: newValue)
            model.selectedDay = day
            let today = Calendar.current.startOfDay(for: .now)
            withAnimation(.smooth) {
                filterDay = day < today ? day : nil
            }
        }
    }

    // MARK: - Readout

    private var dateReadout: some View {
        HStack(alignment: .firstTextBaseline) {
            Button {
                withAnimation(.smooth) { selectedIndex = Self.todayIndex }
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(selectedIndex == Self.todayIndex ? 0 : 1)
            .help("Back to today")

            Spacer()

            Button {
                showAgenda = true
            } label: {
                VStack(spacing: 0) {
                    Text(selectedDay, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.2), value: selectedDay)
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .help("Show this day's meetings")
            .popover(isPresented: $showAgenda, arrowEdge: .top) {
                DayAgendaPopover(day: selectedDay, model: model,
                                 onOpenNote: { note in
                                     showAgenda = false
                                     onOpenNote(note)
                                 },
                                 onArmChanged: onArmChanged)
            }

            Spacer()

            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 13, weight: .semibold))
                .opacity(0)
        }
    }

    // MARK: - Ruler

    private var ruler: some View {
        let dotDays = capturedDays()
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(0..<(Self.pastDays + Self.futureDays + 1), id: \.self) { index in
                    RulerTick(day: Self.day(for: index),
                              hasNotes: dotDays.contains(Calendar.current.startOfDay(for: Self.day(for: index))))
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $selectedIndex, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 130, for: .scrollContent)
        .frame(height: 42)
        .overlay {
            // Fixed center pointer under the readout.
            VStack(spacing: 0) {
                Triangle()
                    .fill(Color.accentColor)
                    .frame(width: 9, height: 5)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 26)
            }
            .allowsHitTesting(false)
        }
        .mask(
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black, location: 0.12),
                                   .init(color: .black, location: 0.88),
                                   .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        )
    }

    /// Start-of-day dates that have captured notes (for ruler dots).
    private func capturedDays() -> Set<Date> {
        let snapshots = (try? context.fetch(FetchDescriptor<MeetingSnapshot>())) ?? []
        let notes = (try? context.fetch(FetchDescriptor<ReviewNote>())) ?? []
        let calendar = Calendar.current
        let fromSnapshots = snapshots.map { calendar.startOfDay(for: $0.occurrenceDate) }
        let fromNotes = notes.map { calendar.startOfDay(for: $0.date) }
        return Set(fromSnapshots + fromNotes)
    }
}

// MARK: - Tick

private struct RulerTick: View {
    let day: Date
    let hasNotes: Bool

    private var isFirstOfMonth: Bool { Calendar.current.component(.day, from: day) == 1 }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(hasNotes ? Color.accentColor : .clear)
                .frame(width: 3.5, height: 3.5)
            RoundedRectangle(cornerRadius: 1)
                .fill(isToday ? Color.red.opacity(0.85) : Color.secondary.opacity(isFirstOfMonth ? 0.75 : 0.4))
                .frame(width: 2, height: isFirstOfMonth ? 20 : 12)
            if isFirstOfMonth {
                Text(day, format: .dateTime.month(.abbreviated))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            } else {
                Color.clear.frame(height: 10)
            }
        }
        .frame(width: 12, height: 42, alignment: .top)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
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
                AgendaEntryRow(entry: entry,
                               onOpenNote: onOpenNote,
                               onArmChanged: { refreshToken += 1; onArmChanged() })
            }
        }
        .id(refreshToken)
        .padding(12)
        .frame(width: 300)
    }
}
