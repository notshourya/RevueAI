import SwiftUI

/// Live illustrations for the welcome slides — real components and the
/// app's own glass, not PNGs. The ruler is a static mock: constructing the
/// real DateRulerView would touch EventKit before permissions are granted.
struct SlideArtView: View {
    let art: SlideArt
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch art {
        case .orb: OrbView(state: .idle, size: 130)
        case .privacy: privacy
        case .liveNote: liveNote
        case .ruler: ruler
        case .assistant: assistant
        }
    }

    private var privacy: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(Theme.success)
                .frame(width: 108, height: 108)
                .glassEffect(.regular, in: Circle())
            HStack(spacing: 8) {
                artChip("No recordings", systemImage: "waveform.slash")
                artChip("On-device", systemImage: "cpu")
            }
        }
    }

    private var liveNote: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                artChip("3 open", systemImage: "circle.dashed")
                artChip("1 done", systemImage: "checkmark.circle.fill", tint: Theme.success)
                artChip("2 questions", systemImage: "questionmark.circle", tint: Theme.warning)
            }
            fakeRow("Refine the canvas styling", tint: Theme.warning)
            fakeRow("Ship the API draft for review", tint: Theme.danger)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func fakeRow(_ text: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12.5, weight: .medium, design: .rounded))
        }
    }

    private var ruler: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                Text(Date.now, format: .dateTime.day())
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red)
            }
            HStack(spacing: 10) {
                ForEach(0..<13, id: \.self) { index in
                    Rectangle()
                        .fill(index == 6 ? Color.red : Color.secondary.opacity(0.5))
                        .frame(width: 2, height: index % 3 == 0 ? 28 : 17)
                }
            }
        }
        .padding(22)
        .glassEffect(.clear.tint(colorScheme == .dark ? .black.opacity(0.35) : .black.opacity(0.16)),
                     in: .rect(cornerRadius: 24))
    }

    private var assistant: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            Text("Which action items are still open?")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .frame(width: 340)
    }

    private func artChip(_ text: String, systemImage: String, tint: Color = .secondary) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
    }
}
