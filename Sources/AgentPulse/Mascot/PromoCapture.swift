import AgentPulseCore
import AppKit
import SwiftUI

/// Геометрия настоящих элементов для офлайн-сценария. В обычном интерфейсе маркеры не создаются.
@MainActor
final class PromoCapture {
    final class WeakView {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }
    var markers: [String: WeakView] = [:]
    var hoverShelfFiles = false

    func rectangles(in host: NSView) -> [String: [Double]] {
        markers.compactMapValues { marker in
            guard let view = marker.view, view.window === host.window else { return nil }
            let r = view.convert(view.bounds, to: host)
            let y = host.isFlipped ? r.minY : host.bounds.height - r.maxY
            return [Double(r.minX - 8), Double(y - 8), Double(r.width), Double(r.height)]
        }
    }
}

private struct PromoCaptureKey: EnvironmentKey {
    static let defaultValue: PromoCapture? = nil
}

extension EnvironmentValues {
    var promoCapture: PromoCapture? {
        get { self[PromoCaptureKey.self] }
        set { self[PromoCaptureKey.self] = newValue }
    }
}

private struct PromoMarker: NSViewRepresentable {
    let id: String
    let capture: PromoCapture
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        capture.markers[id] = PromoCapture.WeakView(view)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

extension View {
    func promoTarget(_ id: String) -> some View {
        modifier(PromoTargetModifier(id: id))
    }
}

private struct PromoTargetModifier: ViewModifier {
    let id: String
    @Environment(\.promoCapture) private var capture
    func body(content: Content) -> some View {
        content.background {
            if let capture { PromoMarker(id: id, capture: capture).allowsHitTesting(false) }
        }
    }
}

/// Детерминированные эффекты промо; обычный интерфейс получает nil.
struct PromoGaugeReveal: Sendable {
    let service: LimitService
    let progress: Double
}
private struct PromoGaugeRevealKey: EnvironmentKey { static let defaultValue: PromoGaugeReveal? = nil }
private struct PromoReadPositionKey: EnvironmentKey { static let defaultValue: Double? = nil }
extension EnvironmentValues {
    var promoGaugeReveal: PromoGaugeReveal? {
        get { self[PromoGaugeRevealKey.self] }
        set { self[PromoGaugeRevealKey.self] = newValue }
    }
    var promoReadPosition: Double? {
        get { self[PromoReadPositionKey.self] }
        set { self[PromoReadPositionKey.self] = newValue }
    }
}
