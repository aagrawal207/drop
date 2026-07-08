import UIKit
import CoreHaptics

/// Central place for game feel. Uses Core Haptics for expressive, custom
/// transients when the device supports it, and falls back to the simpler
/// UIFeedbackGenerator API otherwise (older devices, or when the engine dies).
final class HapticsManager {
    static let shared = HapticsManager()

    /// Confined to the main thread. CoreHaptics' stopped/reset handlers hop to
    /// main before touching it (see prepareEngine); every other access is already
    /// on main. Do not read or write `engine` off the main thread — unsynchronized
    /// cross-thread ARC on this XPC-backed object over-releases it and crashes on
    /// device (an OS_dispatch_mach_msg use-after-free).
    private var engine: CHHapticEngine?
    private let supportsHaptics: Bool

    // Fallback generators (prepared to keep latency low).
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    private init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        prepareEngine()
    }

    private func prepareEngine() {
        guard supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            // The engine can be stopped by the system (e.g. app backgrounded).
            // These handlers fire on an arbitrary CoreHaptics thread, so hop to
            // main before touching `engine` — otherwise the off-main store/read
            // races the main-thread haptic path and over-releases the engine's
            // XPC object (a device-only OS_dispatch_mach_msg use-after-free).
            // Restart it and rebuild patterns lazily on the next play.
            engine.stoppedHandler = { [weak self] _ in
                DispatchQueue.main.async { self?.engine = nil }
            }
            engine.resetHandler = { [weak self] in
                DispatchQueue.main.async { try? self?.engine?.start() }
            }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    /// Call when returning to foreground; the engine may have been torn down.
    func restartIfNeeded() {
        if supportsHaptics && engine == nil { prepareEngine() }
    }

    /// Returns a *running* engine, self-healing along the way: the system stops
    /// the engine (and our stoppedHandler nils it) on backgrounding, calls, Siri,
    /// and audio-session interruptions, so we lazily rebuild it and call the
    /// idempotent start() before every play. Without this, the first stop would
    /// silently degrade all haptics to flat UIKit taps for the rest of the run.
    private func runningEngine() -> CHHapticEngine? {
        guard supportsHaptics else { return nil }
        if engine == nil { prepareEngine() }
        guard let engine else { return nil }
        do { try engine.start() } catch { return nil }
        return engine
    }

    // A one-shot transient with explicit intensity/sharpness, falling back to
    // a UIKit impact of comparable weight.
    private func transient(intensity: Float, sharpness: Float, fallback: UIImpactFeedbackGenerator) {
        guard GameSettings.shared.hapticsEnabled else { return }
        guard let engine = runningEngine() else {
            fallback.impactOccurred()
            fallback.prepare()
            return
        }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0)
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            fallback.impactOccurred()
        }
    }

    /// The ball settles onto a floor. A sharp contact "crack" fused with a short,
    /// low-sharpness continuous "ring" that decays to nothing, so it reads as a
    /// real object landing rather than a bare click — crisp then buzzy. Scales
    /// with impact speed. `vy` is the ball's (usually negative) vertical velocity
    /// at contact. Total duration stays under the 0.10s call-site throttle.
    func land(velocity vy: CGFloat) {
        guard GameSettings.shared.hapticsEnabled else { return }

        // Map |vy| (~60 gentle .. ~1000+ hard) into a clamped 0...1 factor, then
        // ease it so the low-mid range already feels punchy (arcade bias).
        let speed = Float(min(max(abs(vy), 60), 1000))
        let t = (speed - 60) / (1000 - 60)          // 0...1
        let e = t * (2 - t)                          // ease-out; fuller low-mid

        // Strike: sharp + intensity-scaled. High sharpness keeps it crisp = punchy.
        let strikeIntensity = min(max(0.40 + 0.60 * e, 0), 1)   // 0.40 ... 1.0
        let strikeSharpness = min(max(0.55 + 0.40 * e, 0), 1)   // 0.55 ... 0.95

        // Ring: the vibratey body. LOW sharpness -> rounded rumble, not a 2nd tick.
        let ringPeak      = min(max(0.35 + 0.45 * e, 0), 1)     // 0.35 ... 0.80
        let ringSharpness = min(max(0.16 + 0.14 * e, 0), 1)     // 0.16 ... 0.30
        let ringDuration  = TimeInterval(0.055 + 0.105 * Double(e)) // 0.055 ... 0.16 s

        guard let engine = runningEngine() else {
            landFallback(e: e); return
        }

        // Fuse the ring with the strike (~8ms) so they read as one event, not two taps.
        let ringStart: TimeInterval = 0.008

        let strike = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: strikeIntensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: strikeSharpness)
            ],
            relativeTime: 0)

        let ring = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: ringPeak),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: ringSharpness)
            ],
            relativeTime: ringStart,
            duration: ringDuration)

        // Exponential-ish decay so the ring fades out instead of cutting off. The
        // curve is anchored at ringStart; each ControlPoint.relativeTime runs from
        // 0 to ringDuration relative to that anchor.
        let d = ringDuration
        let decay = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.0,      value: 1.0),
                CHHapticParameterCurve.ControlPoint(relativeTime: d * 0.15, value: 0.55),
                CHHapticParameterCurve.ControlPoint(relativeTime: d * 0.40, value: 0.22),
                CHHapticParameterCurve.ControlPoint(relativeTime: d * 0.70, value: 0.07),
                CHHapticParameterCurve.ControlPoint(relativeTime: d,        value: 0.0)
            ],
            relativeTime: ringStart)

        do {
            let pattern = try CHHapticPattern(events: [strike, ring], parameterCurves: [decay])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            landFallback(e: e)
        }
    }

    /// UIKit approximation of the strike + ring for devices without Core Haptics.
    /// One intensity-scaled impact is the "hit"; firmer landings add a single
    /// light tap as the "ring". Kept inside the 0.10s call-site throttle.
    private func landFallback(e: Float) {
        let gen: UIImpactFeedbackGenerator = e < 0.33 ? lightImpact
                                           : e < 0.75 ? mediumImpact : heavyImpact
        gen.impactOccurred(intensity: CGFloat(min(max(0.4 + 0.6 * e, 0), 1)))
        gen.prepare()

        if e > 0.25 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, GameSettings.shared.hapticsEnabled else { return }
                self.lightImpact.impactOccurred(intensity: CGFloat(min(0.2 + 0.3 * e, 1)))
                self.lightImpact.prepare()
            }
        }
    }

    /// Game over — a sharp double buzz.
    func gameOver() {
        guard GameSettings.shared.hapticsEnabled else { return }
        guard let engine = runningEngine() else {
            notification.notificationOccurred(.error)
            return
        }
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
            ], relativeTime: 0.12)
        ]
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            notification.notificationOccurred(.error)
        }
    }

    /// UI taps (buttons).
    func uiTap() {
        transient(intensity: 0.5, sharpness: 0.8, fallback: lightImpact)
    }

    func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        notification.prepare()
    }
}
