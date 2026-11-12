import AppKit
import EmberKit
import SwiftUI

/// Ember's face, drawn from paths so it stays crisp at menu bar size and in the big menu header.
/// Coordinates are in a unit square with y pointing down.
enum MascotGeometry {
    struct Feature {
        let path: CGPath
        let stroked: Bool
    }

    static func body(in rect: CGRect) -> CGPath {
        let t = transform(rect)
        // A flame with a little side lick. Same curves as the app icon (scripts/make-icon.py).
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0.54, y: 0.03))
        p.addCurve(to: CGPoint(x: 0.88, y: 0.62), control1: CGPoint(x: 0.62, y: 0.22), control2: CGPoint(x: 0.88, y: 0.36))
        p.addCurve(to: CGPoint(x: 0.50, y: 0.96), control1: CGPoint(x: 0.88, y: 0.82), control2: CGPoint(x: 0.71, y: 0.96))
        p.addCurve(to: CGPoint(x: 0.12, y: 0.62), control1: CGPoint(x: 0.29, y: 0.96), control2: CGPoint(x: 0.12, y: 0.82))
        p.addCurve(to: CGPoint(x: 0.30, y: 0.26), control1: CGPoint(x: 0.12, y: 0.46), control2: CGPoint(x: 0.22, y: 0.38))
        p.addCurve(to: CGPoint(x: 0.44, y: 0.36), control1: CGPoint(x: 0.34, y: 0.34), control2: CGPoint(x: 0.40, y: 0.38))
        p.addCurve(to: CGPoint(x: 0.54, y: 0.03), control1: CGPoint(x: 0.46, y: 0.24), control2: CGPoint(x: 0.46, y: 0.12))
        p.closeSubpath()
        var xform = t
        return p.copy(using: &xform) ?? p
    }

    static func features(for mood: Mood, in rect: CGRect) -> [Feature] {
        var items: [Feature] = []
        let leftEye = CGPoint(x: 0.36, y: 0.64)
        let rightEye = CGPoint(x: 0.64, y: 0.64)

        func oval(_ c: CGPoint, w: CGFloat = 0.11, h: CGFloat = 0.16) -> Feature {
            Feature(path: CGPath(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), transform: nil), stroked: false)
        }
        func closedEye(_ c: CGPoint) -> Feature {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: c.x - 0.075, y: c.y - 0.01))
            p.addQuadCurve(to: CGPoint(x: c.x + 0.075, y: c.y - 0.01), control: CGPoint(x: c.x, y: c.y + 0.07))
            return Feature(path: p, stroked: true)
        }
        func cross(_ c: CGPoint) -> Feature {
            let p = CGMutablePath()
            let d: CGFloat = 0.055
            p.move(to: CGPoint(x: c.x - d, y: c.y - d)); p.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
            p.move(to: CGPoint(x: c.x + d, y: c.y - d)); p.addLine(to: CGPoint(x: c.x - d, y: c.y + d))
            return Feature(path: p, stroked: true)
        }
        func smile(width: CGFloat = 0.07, depth: CGFloat = 0.06) -> Feature {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0.5 - width, y: 0.79))
            p.addQuadCurve(to: CGPoint(x: 0.5 + width, y: 0.79), control: CGPoint(x: 0.5, y: 0.79 + depth))
            return Feature(path: p, stroked: true)
        }

        switch mood {
        case .awake:
            items = [oval(leftEye), oval(rightEye), smile()]
        case .asleep:
            items = [closedEye(leftEye), closedEye(rightEye)]
        case .wink:
            items = [oval(leftEye), closedEye(rightEye), smile(width: 0.09, depth: 0.08)]
        case .alert:
            items = [oval(leftEye, w: 0.15, h: 0.18), oval(rightEye, w: 0.15, h: 0.18),
                     Feature(path: CGPath(ellipseIn: CGRect(x: 0.46, y: 0.78, width: 0.08, height: 0.08), transform: nil), stroked: false)]
        case .dazed:
            items = [cross(leftEye), cross(rightEye)]
        }

        var t = transform(rect)
        return items.map { Feature(path: $0.path.copy(using: &t) ?? $0.path, stroked: $0.stroked) }
    }

    private static func transform(_ rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height)
    }
}

/// The template image in the menu bar. Features are cut out of the body so it reads at 18 pt.
enum MenuBarIcon {
    private static var cache: [Mood: NSImage] = [:]

    static func image(for mood: Mood) -> NSImage {
        if let cached = cache[mood] { return cached }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let box = rect.insetBy(dx: 0.5, dy: 0.5)
            cg.addPath(MascotGeometry.body(in: box))
            cg.setFillColor(NSColor.black.cgColor)
            cg.fillPath()

            cg.setBlendMode(.clear)
            cg.setLineWidth(1.4)
            cg.setLineCap(.round)
            for feature in MascotGeometry.features(for: mood, in: box) {
                cg.addPath(feature.path)
                if feature.stroked { cg.strokePath() } else { cg.fillPath() }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ember"
        cache[mood] = image
        return image
    }
}

/// The big, coloured Ember in the menu header and the welcome window.
struct MascotView: View {
    var mood: Mood
    var light: LightTarget
    var size: CGFloat = 64

    @State private var breathe = false
    @State private var zFloat = false

    private var colors: [Color] {
        if mood == .dazed { return [Color(white: 0.55), Color(white: 0.35)] }
        switch light {
        case .off: return [Color(red: 0.36, green: 0.22, blue: 0.20), Color(red: 0.18, green: 0.12, blue: 0.12)]
        case .green: return [Color(red: 0.55, green: 0.95, blue: 0.55), Color(red: 0.12, green: 0.62, blue: 0.30)]
        case .amber, .system: return [Color(red: 1.0, green: 0.80, blue: 0.35), Color(red: 0.95, green: 0.38, blue: 0.12)]
        }
    }

    private var glow: Color {
        switch light {
        case .off: return .clear
        case .green: return .green.opacity(0.55)
        case .amber, .system: return .orange.opacity(0.6)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Canvas { context, canvasSize in
                let rect = CGRect(origin: .zero, size: canvasSize)
                let body = Path(MascotGeometry.body(in: rect))
                context.fill(body, with: .linearGradient(
                    Gradient(colors: colors),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                ))
                let ink = Color(red: 0.16, green: 0.08, blue: 0.06)
                for feature in MascotGeometry.features(for: mood, in: rect) {
                    let path = Path(feature.path)
                    if feature.stroked {
                        context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: max(1.5, rect.width * 0.045), lineCap: .round))
                    } else {
                        context.fill(path, with: .color(ink))
                    }
                }
            }
            .frame(width: size, height: size)
            .shadow(color: glow, radius: breathe ? size * 0.22 : size * 0.12)
            .scaleEffect(breathe ? 1.03 : 0.98, anchor: .bottom)

            if mood == .asleep {
                Text("z")
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .offset(x: size * 0.08, y: zFloat ? -size * 0.18 : 0)
                    .opacity(zFloat ? 0.2 : 0.9)
            }
        }
        .accessibilityLabel("Ember looks \(mood.rawValue)")
        .onAppear {
            withAnimation(.easeInOut(duration: mood == .asleep ? 3.2 : 1.8).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false)) {
                zFloat = true
            }
        }
    }
}
