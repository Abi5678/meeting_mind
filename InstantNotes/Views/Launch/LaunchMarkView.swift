//
//  LaunchMarkView.swift
//  Instant Notes
//
// The brand mark and the launch sequence that plays it: a waveform being consumed,
// left to right, by the written lines it turns into. Same 220-unit geometry as the
// app icon generator, so the icon and the splash are the same mark.

import SwiftUI
import MeetingMindKit

/// The mark, drawn in a 220-unit square and scaled to whatever frame it is given.
struct LaunchMarkView: View {
    /// 0 = nothing written yet, 1 = fully written. Sweeps the sound/script boundary.
    var progress: Double
    /// Elapsed seconds, so bars that have not resolved yet still move like live audio.
    var time: Double
    /// 0 = bars flat, 1 = full height. Lets the waveform come up before it converts.
    var rise: Double = 1

    // The shared design space. Mirrored in Tools/makeicon.swift.
    static let barCount = 13
    static let x0: Double = 72
    static let x1: Double = 186
    static let barWidth: Double = 4.5
    static let midline: Double = 112
    static let ruleY: [Double] = [76, 100, 124, 148]
    /// Per-line maximum width, so the last line ends short and the block reads as writing.
    static let lineWidth: [Double] = [114, 114, 98, 64]

    /// The legal-pad margin, matching `VerticalMarginLine` in the editor.
    static let marginRed = Color(red: 0.85, green: 0.25, blue: 0.25)

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

            // The page itself. Cream in light, near-black in dark, same as the editor canvas.
            context.fill(
                Path(roundedRect: rect(10, 10, 200, 200), cornerRadius: 46 * s),
                with: .color(Color(paperTint: .cream))
            )

            // The page is ruled before anything is written on it.
            var rules = Path()
            for y in Self.ruleY {
                rules.move(to: CGPoint(x: Self.x0 * s, y: y * s))
                rules.addLine(to: CGPoint(x: Self.x1 * s, y: y * s))
            }
            context.stroke(rules, with: .color(Color("RuleColor")), lineWidth: 1.25 * s)

            // The margin rail deepens as the page fills.
            var rail = Path()
            rail.move(to: CGPoint(x: 58 * s, y: 36 * s))
            rail.addLine(to: CGPoint(x: 58 * s, y: 184 * s))
            context.stroke(
                rail,
                with: .color(Self.marginRed.opacity(0.35 + 0.55 * progress)),
                style: StrokeStyle(lineWidth: 2.5 * s, lineCap: .round)
            )

            let boundary = Self.x0 + progress * (Self.x1 - Self.x0)
            let ink = Color("InkColor")

            // Written lines, revealed left to right.
            for (i, y) in Self.ruleY.enumerated() {
                let w = min(max(boundary - Self.x0, 0), Self.lineWidth[i])
                guard w > 0.5 else { continue }
                context.fill(
                    Path(roundedRect: rect(Self.x0, y - 3.5, w, 3.5), cornerRadius: 1.75 * s),
                    with: .color(ink.opacity(0.88))
                )
            }

            // Waveform, consumed left to right. `alive` softens each bar as the boundary reaches it.
            let pitch = (Self.x1 - Self.x0 - Self.barWidth) / Double(Self.barCount - 1)
            for i in 0..<Self.barCount {
                let bx = Self.x0 + Double(i) * pitch
                let alive = min(max((bx - boundary) / 22, 0), 1)
                guard alive > 0.01 else { continue }
                let h = 6 + Self.amplitude(i, time) * 74 * alive * rise
                context.fill(
                    Path(roundedRect: rect(bx, Self.midline - h / 2, Self.barWidth, h),
                         cornerRadius: Self.barWidth / 2 * s),
                    with: .color(ink.opacity(0.92 * alive))
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
            Color("PaperBackground")
                .ignoresSafeArea()

            if reduceMotion {
                VStack(spacing: 22) {
                    LaunchMarkView(progress: 1, time: 0, rise: 1)
                        .frame(width: 176, height: 176)
                    wordmark
                }
            } else {
                // Static mark+wordmark underneath so the first paint is never blank if TimelineView lags.
                VStack(spacing: 22) {
                    LaunchMarkView(progress: 0, time: 0, rise: 1)
                        .frame(width: 176, height: 176)
                    wordmark
                }
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(start)
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

    /// The product name. Weight carries the split rather than colour, so it stays legible
    /// on either appearance without a second palette.
    private var wordmark: some View {
        HStack(spacing: 0) {
            Text("Instant").fontWeight(.light)
            Text(" Notes").fontWeight(.heavy)
        }
        .font(.system(size: 32))
        .kerning(-0.6)
        .foregroundStyle(Color("InkColor"))
        .accessibilityElement()
        .accessibilityLabel("Instant Notes")
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
