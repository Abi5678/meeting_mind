//
//  LaunchMarkView.swift
//  Quolio
//
// The brand mark and the launch sequence that plays it: a speech bubble in which a live
// waveform is written up, left to right, as a bulleted recap. Same geometry as the app icon
// generator (Tools/makeicon.swift), mapped from its 1024 tile onto 10...210 here, so the
// icon and the splash are the same mark.

import SwiftUI

/// The mark, drawn in a 220-unit square and scaled to whatever frame it is given.
struct LaunchMarkView: View {
    /// 0 = nothing written yet, 1 = fully written. Sweeps the sound/recap boundary.
    var progress: Double
    /// Elapsed seconds, so bars that have not resolved yet still move like live audio.
    var time: Double
    /// 0 = bars flat, 1 = full height. Lets the waveform come up before it converts.
    var rise: Double = 1

    // The shared design space. Mirrored in Tools/makeicon.swift.
    static let bubble = CGRect(x: 43.2, y: 47.1, width: 133.6, height: 101.6)
    static let rowY: [Double] = [78.75, 98.28, 117.8]
    static let bulletX: Double = 63.1
    static let bulletRadius: Double = 5.86
    static let lineHeight: Double = 10.5
    static let barCount = 9
    static let x0: Double = 76.4
    static let x1: Double = 164.7
    static let barWidth: Double = 7.8
    /// Per-row width once written, shortening down the list so it reads as a recap.
    static let lineWidth: [Double] = [88, 72, 48]
    /// Each row starts a beat after the one above, so the recap is written a line at a time.
    static let rowLag: Double = 12

    // Fixed rather than adaptive: the mark is the icon, and the icon does not change in dark mode.
    static let tileTop = Color(red: 0.318, green: 0.443, blue: 0.894)
    static let tileBottom = Color(red: 0.176, green: 0.267, blue: 0.667)
    static let paper = Color(red: 0.99, green: 0.97, blue: 0.91)
    static let ink = Color(red: 0.110, green: 0.110, blue: 0.120)
    static let accent = Color(red: 0.231, green: 0.357, blue: 0.800)

    /// Layered sines rather than random noise, so the mark animates identically every launch.
    static func amplitude(_ i: Int, _ t: Double) -> Double {
        let u = Double(i) / Double(barCount - 1)
        let a = sin(t * 2.6 + Double(i) * 0.85) * 0.50
              + sin(t * 1.35 + Double(i) * 0.42) * 0.34
              + sin(t * 4.10 + Double(i) * 1.60) * 0.16
        let envelope = 0.45 + 0.55 * sin(.pi * u)
        return (0.3 + 0.7 * abs(a)) * envelope
    }

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 220

            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
                CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
            }
            func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // The tile, cornered like a home-screen icon.
            context.fill(
                Path(roundedRect: rect(10, 10, 200, 200), cornerRadius: 45 * s, style: .continuous),
                with: .linearGradient(Gradient(colors: [Self.tileTop, Self.tileBottom]),
                                      startPoint: point(0, 10), endPoint: point(0, 210))
            )

            // The bubble and its tail, lifted off the tile.
            let shape = Path(roundedRect: rect(Self.bubble.minX, Self.bubble.minY,
                                               Self.bubble.width, Self.bubble.height),
                             cornerRadius: 31.25 * s)
            var tail = Path()
            tail.move(to: point(61.2, 138.9))
            tail.addQuadCurve(to: point(48.3, 174.5), control: point(62.3, 162.3))
            tail.addQuadCurve(to: point(94.0, 146.7), control: point(76.4, 166.3))
            tail.closeSubpath()
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: Color(red: 0.05, green: 0.08, blue: 0.25).opacity(0.35),
                                        radius: 4.7 * s, y: 3.5 * s))
                // Filled apart: joined into one path, the tail's winding would punch a hole.
                layer.fill(shape, with: .color(Self.paper))
                layer.fill(tail, with: .color(Self.paper))
            }

            let boundary = Self.x0 + progress * (Self.x1 - Self.x0)

            // Bullets pop in as their row starts; written lines follow them.
            for (i, y) in Self.rowY.enumerated() {
                let written = boundary - Self.x0 - Double(i) * Self.rowLag
                let pop = min(max(written / 8, 0), 1)
                if pop > 0.01 {
                    let r = Self.bulletRadius * pop
                    context.fill(Path(ellipseIn: rect(Self.bulletX - r, y - r, r * 2, r * 2)),
                                 with: .color(Self.accent))
                }
                let w = min(max(written, 0), Self.lineWidth[i])
                guard w > 0.5 else { continue }
                context.fill(
                    Path(roundedRect: rect(Self.x0, y - Self.lineHeight / 2, max(w, Self.lineHeight), Self.lineHeight),
                         cornerRadius: Self.lineHeight / 2 * s),
                    with: .color(Self.ink)
                )
            }

            // Waveform, consumed left to right. `alive` softens each bar as the boundary reaches it.
            let pitch = (Self.x1 - Self.x0 - Self.barWidth) / Double(Self.barCount - 1)
            for i in 0..<Self.barCount {
                let bx = Self.x0 + Double(i) * pitch
                let alive = min(max((bx - boundary) / 22, 0), 1)
                guard alive > 0.01 else { continue }
                let h = Self.barWidth + Self.amplitude(i, time) * 52 * alive * rise
                context.fill(
                    Path(roundedRect: rect(bx, Self.rowY[1] - h / 2, Self.barWidth, h),
                         cornerRadius: Self.barWidth / 2 * s),
                    with: .color(Self.ink.opacity(alive))
                )
            }
        }
        .accessibilityHidden(true)
    }
}

/// Plays the mark once on launch, then gets out of the way.
struct LaunchSplashView: View {
    /// Called when the sequence has finished and the splash can be removed.
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    // The sequence, in seconds.
    private static let fadeIn = 0.30
    private static let riseEnd = 0.55
    private static let resolveStart = 0.65
    private static let resolveEnd = 1.95
    private static let nameStart = 1.05
    private static let nameEnd = 1.70
    // Long enough that the name is fully up and readable before anything starts leaving.
    private static let fadeOutStart = 3.00
    private static let total = 3.50

    /// Held still and shown for a moment, for anyone who has asked the system for less motion.
    private static let reducedTotal = 1.20

    var body: some View {
        ZStack {
            if reduceMotion {
                Color("PaperBackground")
                    .ignoresSafeArea()
                VStack(spacing: 22) {
                    LaunchMarkView(progress: 1, time: 0, rise: 1)
                        .frame(width: 176, height: 176)
                    wordmark
                }
            } else {
                // The paper sits inside the timeline so the whole splash fades out onto the list.
                // TimelineView draws its first frame straight away, with the mark and name already up.
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(start)
                    ZStack {
                        Color("PaperBackground")
                            .ignoresSafeArea()
                        VStack(spacing: 22) {
                            LaunchMarkView(
                                progress: Self.ease(Self.span(t, Self.resolveStart, Self.resolveEnd)),
                                time: t,
                                rise: max(0.55, Self.ease(Self.span(t, 0, Self.riseEnd)))
                            )
                            .frame(width: 176, height: 176)
                            .scaleEffect(0.94 + 0.06 * Self.ease(Self.span(t, 0, Self.fadeIn)))

                            // Wordmark visible early; fully opaque by nameEnd, held until fadeOutStart (≥0.8s).
                            wordmark
                                .opacity(max(0.85, Self.ease(Self.span(t, 0.15, Self.nameEnd))))
                        }
                    }
                    .opacity(Self.opacity(at: t))
                }
            }
        }
        .task {
            let seconds = reduceMotion ? Self.reducedTotal : Self.total
            try? await Task.sleep(for: .seconds(seconds))
            onFinish()
        }
    }

    /// The product name. Rounded to match the bubble; the "Q" takes the accent, the colour
    /// of the recap's bullets.
    private var wordmark: some View {
        HStack(spacing: 0) {
            Text("Q").foregroundStyle(Color("AccentColor"))
            Text("uolio").foregroundStyle(Color("InkColor"))
        }
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .kerning(-0.8)
        .accessibilityElement()
        .accessibilityLabel("Quolio")
    }

    /// Where `t` sits between two times, clamped to 0...1.
    private static func span(_ t: Double, _ from: Double, _ to: Double) -> Double {
        min(max((t - from) / (to - from), 0), 1)
    }

    private static func ease(_ x: Double) -> Double {
        x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }

    /// Opaque from the first frame (avoids a white flash); only fades out at the end.
    private static func opacity(at t: Double) -> Double {
        1 - span(t, fadeOutStart, total)
    }
}
