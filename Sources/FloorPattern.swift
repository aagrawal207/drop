import CoreGraphics
import Foundation

/// One floor's hole layout in field coordinates (x = 0 is the left wall).
/// Sliding floors move the whole node; `gapCenters` are the rest positions.
struct FloorSpec: Equatable {
    enum Kind: Hashable { case standard, narrow, twoGap, sliding }

    var kind: Kind
    var gapCenters: [CGFloat]
    var gapWidth: CGFloat
    var slideAmplitude: CGFloat = 0
    var slidePeriod: Double = 0
    var slidePhase: Double = 0

    static func standard(at x: CGFloat, gapWidth: CGFloat) -> FloorSpec {
        FloorSpec(kind: .standard, gapCenters: [x], gapWidth: gapWidth)
    }

    var isHard: Bool { kind == .narrow || kind == .sliding }

    /// Every x the ball can leave this floor through, including a slide's full travel.
    var exitRange: ClosedRange<CGFloat> {
        let lo = (gapCenters.min() ?? 0) - slideAmplitude
        let hi = (gapCenters.max() ?? 0) + slideAmplitude
        return lo...hi
    }

    /// Node x offset at run time `t`. A sine keeps the motion smooth at the turnarounds,
    /// which matters because a moved static body is a teleport to the solver.
    func slideOffset(at t: Double) -> CGFloat {
        guard slideAmplitude > 0, slidePeriod > 0 else { return 0 }
        return slideAmplitude * CGFloat(sin(slidePhase + 2 * Double.pi * t / slidePeriod))
    }
}

/// When each floor type phases in, by depth (floors generated this run).
struct FloorSchedule {
    struct Ramp {
        let from: Int
        let startChance: Double
        let endChance: Double
        let span: Int

        func chance(at depth: Int) -> Double {
            guard depth >= from else { return 0 }
            let f = min(1, Double(depth - from) / Double(span))
            return startChance + (endChance - startChance) * f
        }

        /// 0 at first appearance, 1 once the type is at its hardest.
        func severity(at depth: Int, over floors: Int) -> CGFloat {
            CGFloat(min(1, max(0, Double(depth - from) / Double(floors))))
        }
    }

    let narrow: Ramp
    let twoGap: Ramp
    let sliding: Ramp
    /// Narrowest hole on iPhone widths; the ball is 34pt across.
    let narrowMinWidth: CGFloat
    let narrowSeverityFloors: Int
    let slideMaxFraction: CGFloat
    let slidePeriodRange: ClosedRange<Double>
    let slideSeverityFloors: Int

    // Ranked passes floor ~20 at 21s, ~45 at 38s and ~70 at 52s (camera already ~320pt/s).
    static let ranked = FloorSchedule(
        narrow: Ramp(from: 25, startChance: 0.08, endChance: 0.22, span: 100),
        twoGap: Ramp(from: 45, startChance: 0.06, endChance: 0.12, span: 80),
        sliding: Ramp(from: 70, startChance: 0.06, endChance: 0.18, span: 90),
        narrowMinWidth: 66, narrowSeverityFloors: 100,
        slideMaxFraction: 0.14, slidePeriodRange: 4.5...6.5, slideSeverityFloors: 90)

    static let zen = FloorSchedule(
        narrow: Ramp(from: 40, startChance: 0.05, endChance: 0.14, span: 140),
        twoGap: Ramp(from: 60, startChance: 0.06, endChance: 0.12, span: 100),
        sliding: Ramp(from: 110, startChance: 0.04, endChance: 0.10, span: 140),
        narrowMinWidth: 72, narrowSeverityFloors: 160,
        slideMaxFraction: 0.10, slidePeriodRange: 5.5...7.5, slideSeverityFloors: 140)
}

/// Pure floor-layout generator; the scene owns node building and the clock.
struct FloorPatternGenerator {
    let fieldWidth: CGFloat
    let schedule: FloorSchedule
    let standardGapWidth: CGFloat
    let sideMargin: CGFloat
    /// The first floor is laid by the scene, so generated floors start at depth 1.
    private(set) var depth = 1
    private(set) var exit: ClosedRange<CGFloat>
    private var lastWasHard = false
    private var seen: Set<FloorSpec.Kind> = []

    init(fieldWidth: CGFloat, schedule: FloorSchedule, firstGapX: CGFloat,
         standardGapWidth: CGFloat = 82, sideMargin: CGFloat = 6) {
        self.fieldWidth = fieldWidth
        self.schedule = schedule
        self.standardGapWidth = standardGapWidth
        self.sideMargin = sideMargin
        exit = firstGapX...firstGapX
    }

    var maxStep: CGFloat { fieldWidth * 0.34 }
    var widthScale: CGFloat { max(1, fieldWidth / 440) }
    /// iPad steering is faster (scaled with width), so precise threading gets a little more room.
    var narrowMinWidth: CGFloat {
        min(standardGapWidth - 6, schedule.narrowMinWidth + 12 * (widthScale - 1))
    }
    var narrowMaxWidth: CGFloat { standardGapWidth - 4 }
    /// Wide enough between holes that two-gap floors read as two holes, not a split one.
    var minPlankBetweenGaps: CGFloat { fieldWidth * 0.2 }

    mutating func next<R: RandomNumberGenerator>(using rng: inout R) -> FloorSpec {
        let kind = pickKind(using: &rng)
        let spec = build(kind, using: &rng) ?? standard(using: &rng)
        if spec.kind != .standard { seen.insert(spec.kind) }
        lastWasHard = spec.isHard
        exit = spec.exitRange
        depth += 1
        return spec
    }

    private func pickKind<R: RandomNumberGenerator>(using rng: inout R) -> FloorSpec.Kind {
        let n = lastWasHard ? 0 : schedule.narrow.chance(at: depth)
        let s = lastWasHard ? 0 : schedule.sliding.chance(at: depth)
        let t = schedule.twoGap.chance(at: depth)
        guard n + s + t > 0 else { return .standard }
        let u = Double.random(in: 0..<1, using: &rng)
        if u < n { return .narrow }
        if u < n + t { return .twoGap }
        if u < n + t + s { return .sliding }
        return .standard
    }

    /// Hole centres reachable from every exit point of the previous floor.
    func window(halfWidth h: CGFloat) -> ClosedRange<CGFloat>? {
        let low = max(h + sideMargin, exit.upperBound - maxStep)
        let high = min(fieldWidth - h - sideMargin, exit.lowerBound + maxStep)
        return low <= high ? low...high : nil
    }

    private func build<R: RandomNumberGenerator>(_ kind: FloorSpec.Kind,
                                                 using rng: inout R) -> FloorSpec? {
        let firstTime = !seen.contains(kind)
        switch kind {
        case .standard:
            return nil
        case .narrow:
            let sev = schedule.narrow.severity(at: depth, over: schedule.narrowSeverityFloors)
            let hi = narrowMaxWidth
            let lo = firstTime ? hi : hi - (hi - narrowMinWidth) * sev
            let w = lo < hi ? CGFloat.random(in: lo...hi, using: &rng) : hi
            guard let win = window(halfWidth: w / 2) else { return nil }
            let x = CGFloat.random(in: win, using: &rng)
            return FloorSpec(kind: .narrow, gapCenters: [x], gapWidth: w)
        case .twoGap:
            let w = standardGapWidth
            guard let win = window(halfWidth: w / 2) else { return nil }
            let minSep = w + minPlankBetweenGaps
            // Leaves the following floor a window at least one hole wide.
            let maxSep = min(win.upperBound - win.lowerBound, 2 * maxStep - w,
                             firstTime ? minSep : minSep + fieldWidth * 0.12)
            guard maxSep >= minSep else { return nil }
            let sep = CGFloat.random(in: minSep...maxSep, using: &rng)
            let left = CGFloat.random(in: win.lowerBound...(win.upperBound - sep), using: &rng)
            return FloorSpec(kind: .twoGap, gapCenters: [left, left + sep], gapWidth: w)
        case .sliding:
            let w = standardGapWidth
            guard let win = window(halfWidth: w / 2) else { return nil }
            let sev = schedule.sliding.severity(at: depth, over: schedule.slideSeverityFloors)
            let minAmp = fieldWidth * 0.05
            let maxAmp = firstTime ? minAmp
                : minAmp + (fieldWidth * schedule.slideMaxFraction - minAmp) * sev
            var amp = minAmp < maxAmp ? CGFloat.random(in: minAmp...maxAmp, using: &rng) : minAmp
            amp = min(amp, (win.upperBound - win.lowerBound) / 2)
            guard amp >= fieldWidth * 0.04 else { return nil }
            let x = CGFloat.random(in: (win.lowerBound + amp)...(win.upperBound - amp), using: &rng)
            let periods = schedule.slidePeriodRange
            let slowest = periods.upperBound
            let fastest = slowest - (slowest - periods.lowerBound) * Double(sev)
            let period = firstTime ? slowest : Double.random(in: fastest...slowest, using: &rng)
            let phase = Double.random(in: 0..<(2 * Double.pi), using: &rng)
            return FloorSpec(kind: .sliding, gapCenters: [x], gapWidth: w,
                             slideAmplitude: amp, slidePeriod: period, slidePhase: phase)
        }
    }

    private func standard<R: RandomNumberGenerator>(using rng: inout R) -> FloorSpec {
        let w = standardGapWidth
        // Degenerate scenes (width < gap + margins) have no window; centre the gap.
        guard let win = window(halfWidth: w / 2) else {
            return .standard(at: fieldWidth / 2, gapWidth: w)
        }
        return .standard(at: CGFloat.random(in: win, using: &rng), gapWidth: w)
    }
}
