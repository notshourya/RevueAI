import SwiftUI
import AppKit

// MARK: - Anchor plumbing

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Registers this view as a tour target under `id`. nil is a no-op so
    /// callers can register conditionally (e.g. only the first row).
    func tourAnchor(_ id: String?) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { anchor in
            guard let id else { return [:] }
            return [id: anchor]
        }
    }

    /// Attaches the guided-tour overlay; call once, on the shell root.
    func tourOverlay(controller: TourController,
                     onAction: @escaping (String) -> Void = { _ in }) -> some View {
        modifier(TourOverlayModifier(controller: controller, onAction: onAction))
    }

    fileprivate func reverseMask<M: View>(@ViewBuilder _ mask: () -> M) -> some View {
        self.mask {
            Rectangle()
                .overlay(mask().blendMode(.destinationOut))
                .compositingGroup()
        }
    }
}

private extension NSView {
    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let nested = subview.firstSubview(of: type) { return nested }
        }
        return nil
    }
}

// MARK: - Overlay modifier

struct TourOverlayModifier: ViewModifier {
    let controller: TourController
    var onAction: (String) -> Void

    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(TourAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if let stop = controller.current {
                        TourSpotlight(stop: stop,
                                      rect: rect(for: stop, anchors: anchors, proxy: proxy),
                                      size: proxy.size,
                                      controller: controller,
                                      onAction: onAction)
                    }
                }
                .ignoresSafeArea()
                // Only intercept events while a step is on screen; otherwise the
                // window-spanning overlay would swallow every click and block
                // sidebar scrolling even when the tour is idle.
                .allowsHitTesting(controller.current != nil)
                .background(WindowProbe(window: $window))
            }
    }

    /// SwiftUI anchors win; the two toolbar ids fall back to AppKit lookup.
    /// nil (never registered / not found) renders a centered card instead.
    private func rect(for stop: TourStop,
                      anchors: [String: Anchor<CGRect>],
                      proxy: GeometryProxy) -> CGRect? {
        guard let id = stop.anchorID else { return nil }
        if let anchor = anchors[id] { return proxy[anchor] }
        switch id {
        case "assistant-search":
            return toolbarRect(proxy: proxy, last: false) { isSearchItem($0) }
        case "export-menu":
            // After ToolbarSearchCenterer's reorder the export menu is the
            // trailing-most real item, so match from the end.
            let spaces: Set<NSToolbarItem.Identifier> = [.flexibleSpace, .space]
            return toolbarRect(proxy: proxy, last: true) { item in
                !(item is NSTrackingSeparatorToolbarItem)
                    && !spaces.contains(item.itemIdentifier)
                    && !isSearchItem(item)
            }
        default:
            return nil
        }
    }

    private func isSearchItem(_ item: NSToolbarItem) -> Bool {
        item is NSSearchToolbarItem || item.view?.firstSubview(of: NSSearchField.self) != nil
    }

    /// Converts a toolbar item's AppKit frame into the overlay's top-left
    /// coordinate space. Returns nil when anything is missing — the stop
    /// then renders as a centered card (spec's fallback).
    private func toolbarRect(proxy: GeometryProxy, last: Bool,
                             matching: (NSToolbarItem) -> Bool) -> CGRect? {
        guard let window,
              let toolbar = window.toolbar,
              let contentView = window.contentView else { return nil }
        let items = toolbar.items
        guard let item = last ? items.last(where: matching) : items.first(where: matching),
              let view = item.view, view.window === window else { return nil }
        let inWindow = view.convert(view.bounds, to: nil)
        let flipped = CGRect(x: inWindow.minX,
                             y: contentView.frame.height - inWindow.maxY,
                             width: inWindow.width,
                             height: inWindow.height)
        let global = proxy.frame(in: .global)
        return flipped.offsetBy(dx: -global.minX, dy: -global.minY)
    }
}

/// Probe capturing the hosting NSWindow. Its NSView must be transparent to
/// AppKit hit testing: as a real subview spanning the window it would
/// otherwise swallow every click and scroll before SwiftUI sees them.
private struct WindowProbe: NSViewRepresentable {
    @Binding var window: NSWindow?

    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        DispatchQueue.main.async { [weak view] in window = view?.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if window !== view.window {
            DispatchQueue.main.async { [weak view] in window = view?.window }
        }
    }
}

// MARK: - Spotlight + callout

private struct TourSpotlight: View {
    let stop: TourStop
    let rect: CGRect?
    let size: CGSize
    let controller: TourController
    var onAction: (String) -> Void

    private static let calloutWidth: CGFloat = 300
    private static let calloutEstimatedHeight: CGFloat = 150

    var body: some View {
        ZStack {
            backdrop
            callout
                .position(calloutPosition)
        }
        .transition(.opacity)
        .animation(.smooth(duration: 0.3), value: stop.id)
    }

    private var backdrop: some View {
        Color.black.opacity(0.42)
            .reverseMask {
                if let rect {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .frame(width: rect.width + 18, height: rect.height + 18)
                        .position(x: rect.midX, y: rect.midY)
                        .blur(radius: 2.5)
                }
            }
            // Swallow clicks so the tour is modal until Next/Skip.
            .contentShape(Rectangle())
            .onTapGesture {}
    }

    private var callout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STEP \(controller.index + 1) OF \(controller.stops.count)")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Text(stop.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(stop.body)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Skip tour") {
                    withAnimation(.smooth) { controller.skip() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.tertiary)
                .keyboardShortcut(.cancelAction)

                Spacer()

                if let actionTitle = stop.actionTitle {
                    Button(actionTitle) {
                        let id = stop.id
                        withAnimation(.smooth) { controller.advance() }
                        onAction(id)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(controller.isLastStop ? "Done" : "Next") {
                    withAnimation(.smooth) { controller.advance() }
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: Self.calloutWidth)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    /// Places the callout beside the target on the stop's `arrowEdge` side,
    /// clamped to the window; centered when there is no target rect.
    private var calloutPosition: CGPoint {
        guard let rect else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let halfW = Self.calloutWidth / 2
        let halfH = Self.calloutEstimatedHeight / 2
        var point: CGPoint
        switch stop.arrowEdge {
        case .top:
            point = CGPoint(x: rect.midX, y: rect.minY - halfH - 22)
        case .bottom:
            point = CGPoint(x: rect.midX, y: rect.maxY + halfH + 22)
        case .leading:
            point = CGPoint(x: rect.minX - halfW - 22, y: rect.midY)
        case .trailing:
            point = CGPoint(x: rect.maxX + halfW + 22, y: rect.midY)
        }
        point.x = min(max(point.x, halfW + 16), size.width - halfW - 16)
        point.y = min(max(point.y, halfH + 16), size.height - halfH - 16)
        return point
    }
}
