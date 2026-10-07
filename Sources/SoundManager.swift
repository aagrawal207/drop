import AVFoundation
import CoreGraphics

/// Procedurally-synthesised game sounds — no audio assets to bundle. Tones are
/// pre-rendered into PCM buffers once at init and played through a small pool of
/// player nodes so overlapping sounds (a bounce during a score jingle) don't cut
/// each other off.
///
/// Lifecycle mirrors the hardened HapticsManager pattern: all engine access is on
/// the main thread, the engine is (re)started lazily before every sound, and a
/// foreground hook rebuilds it after the system tears audio down on backgrounding.
final class SoundManager {
    static let shared = SoundManager()

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    /// True while the AVAudioSession is (believed) configured and active. Reset
    /// on interruption-ended so the session is re-activated, not just restarted.
    private var sessionActive = false

    // Pre-rendered buffers.
    /// Rising notes for +1/+2/+3, one set per streak pitch level (see streakSemitones).
    private var blipSets: [[AVAudioPCMBuffer]] = []
    /// The "big" sound for +4 and up, per streak pitch level.
    private var chimes: [AVAudioPCMBuffer] = []
    /// The every-50 milestone: a two-note rising bell.
    private var milestoneChime: AVAudioPCMBuffer!
    /// Pitch offset per streak level. Scale steps rather than semitones keep a long streak
    /// sounding musical, and the cap stops it climbing into a shrill register.
    private let streakSemitones: [Double] = [0, 2, 4, 5, 7, 9]
    /// Wooden toks at three impact intensities (soft / medium / hard). A hard
    /// hit isn't just louder — it's brighter and rings a touch longer, which is
    /// how the ear judges impact energy. Selected by impact speed in bounce().
    private var bounceBufs: [AVAudioPCMBuffer] = []

    private init() {
        renderBuffers()
        buildGraph()
        // The system deactivates our session on interruptions (calls, Siri) and
        // stops the engine on route changes (unplugging headphones). The lazy
        // ensureRunning() before each play self-heals eventually, but the first
        // sound after such an event can be swallowed if engine.start() fails
        // that frame. Rebuild eagerly instead.
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification, object: nil)
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        DispatchQueue.main.async { [weak self] in
            self?.sessionActive = false   // force re-activation, not just restart
            self?.ensureRunning()
        }
    }

    @objc private func handleRouteChange() {
        DispatchQueue.main.async { [weak self] in self?.ensureRunning() }
    }

    // MARK: - Public API

    /// Play the score sound for a points gain. +1/+2/+3 play a soft rising pip
    /// that many times; a jump of +4 or more plays one mellow "done" note. Kept
    /// gentle on purpose — a quiet tick, not a slot-machine payout. Both rise in pitch from
    /// the 3rd clean pass in a row, so a building streak is audible.
    func score(gained: Int, streak: Int = 0) {
        guard GameSettings.shared.scoreSoundEnabled, gained > 0 else { return }
        let level = min(max(streak - 2, 0), streakSemitones.count - 1)
        if gained >= 4 {
            play(chimes[level], volume: 0.4)
            return
        }
        let blips = blipSets[level]
        let n = min(gained, blips.count)           // 1...3
        for i in 0..<n {
            let buf = blips[i]
            if i == 0 {
                play(buf, volume: 0.4)
            } else {
                // Space the repeats a touch wider so they read as a soft sequence,
                // not a rapid-fire jingle.
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.11) { [weak self] in
                    self?.play(buf, volume: 0.4)
                }
            }
        }
    }

    /// Every-50 milestone bell. Gated on either sound toggle: a player who muted only the
    /// score pips still hears the game, and one who muted both hears nothing.
    func milestone() {
        let settings = GameSettings.shared
        guard settings.scoreSoundEnabled || settings.bounceSoundEnabled else { return }
        play(milestoneChime, volume: 0.32)
    }

    /// Play the bounce "tok". Two things scale with impact speed so big bounces
    /// read clearly bigger than small ones:
    /// - the buffer: soft (dull, short) / medium / hard (brighter, longer),
    /// - the gain, mapped in the dB domain. Linear gain crams most of the
    ///   audible change into the bottom of the range; equal dB steps give equal
    ///   perceived-loudness steps. 24 dB of range: whisper 0.06 ... full 1.0.
    /// Uses the same normalizer as HapticsManager.land so ear and hand agree.
    func bounce(velocity: CGFloat) {
        guard GameSettings.shared.bounceSoundEnabled else { return }
        let e = Self.impactNormalized(velocity)
        let buf = bounceBufs[e < 0.35 ? 0 : e < 0.75 ? 1 : 2]
        let gainDB = -24 + 24 * e                   // -24 dB ... 0 dB
        play(buf, volume: pow(10, gainDB / 20))     // 0.063 ... 1.0
    }

    /// Impact speed -> 0...1, identical to the haptic mapping in
    /// HapticsManager.land (range 60...1000, ease-out for arcade punch in the
    /// low-mid range). Keep the two in sync — a mismatch makes a landing feel
    /// big in the hand but sound small, or vice versa.
    static func impactNormalized(_ velocity: CGFloat) -> Float {
        let speed = Float(min(max(abs(velocity), 60), 1000))
        let t = (speed - 60) / (1000 - 60)
        return t * (2 - t)                           // ease-out
    }

    /// Rebuild the audio session/engine when returning to the foreground; the
    /// system tears audio down on backgrounding.
    func restartIfNeeded() {
        ensureRunning()
    }

    /// Activate the audio session + start the engine ahead of time (call at
    /// launch, while the menu is up). Activating the AVAudioSession on the first
    /// sound is the main cause of a hitch at the start of the first run.
    func warmUp() {
        ensureRunning()
    }

    // MARK: - Engine

    private func buildGraph() {
        // Six voices is plenty of headroom for overlapping short sounds.
        for _ in 0..<6 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
    }

    /// Idempotent: activate the audio session, start the engine, and make sure
    /// every player node is running. Called before each sound so an interruption
    /// or route change (which stops the engine) self-heals on the next play.
    private func ensureRunning() {
        if !sessionActive {
            let session = AVAudioSession.sharedInstance()
            // .ambient => obeys the mute switch and mixes with other audio, which
            // is the right manners for a casual game's sound effects.
            do {
                try session.setCategory(.ambient, options: [.mixWithOthers])
                try session.setActive(true)
                sessionActive = true
            } catch {
                // Leave sessionActive false so the next play retries activation.
                // (It used to latch true via try?, so one failure was permanent.)
                return
            }
        }
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return }
        }
        for node in players where !node.isPlaying {
            node.play()
        }
    }

    private func play(_ buffer: AVAudioPCMBuffer, volume: Float) {
        ensureRunning()
        guard engine.isRunning else { return }
        let node = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        node.volume = min(max(volume, 0), 1)
        // .interrupts replaces whatever (if anything) is tailing on this reused
        // node so the new hit is immediate; round-robin keeps that rare.
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    // MARK: - Synthesis

    private func renderBuffers() {
        // Soft rising pips for +1/+2/+3. Pure sines in a warm mid register with
        // whole-tone steps, so a streak nudges upward rather than pinging like coins.
        for semis in streakSemitones {
            let k = pow(2, semis / 12)
            blipSets.append([392.00, 440.00, 493.88].map { f in   // G4, A4, B4
                tone(partials: [(f * k, 0.8)], duration: 0.15, decay: 17, attack: 0.010)
            })
            // The "+4 or more" sound: a single mellow note (root + a quiet fifth for
            // warmth), same register as the pips so it reads as a soft resolution.
            chimes.append(tone(partials: [(523.25 * k, 0.7), (784.00 * k, 0.18)],   // C5 + soft G5
                               duration: 0.42, decay: 9, attack: 0.010))
        }
        // An octave above the pips so it stands apart from scoring, with a faint octave
        // partial for a bell edge; slow decay lets the second note ring out.
        milestoneChime = notes([(783.99, 0), (1046.50, 0.09)],   // G5 then C6
                               partials: [(1, 0.55), (2, 0.08)],
                               duration: 0.6, decay: 7, attack: 0.006)
        // Wooden "tok" at three intensities. All share the low ~196 Hz body so
        // they read as the same object; what changes is brightness (upper
        // partials), length, and decay — a soft graze is dull and dead, a hard
        // slam is brighter with a slightly dropped fundamental (big objects
        // ring lower) and a longer tail.
        bounceBufs = [
            // soft: dull, very short
            tone(partials: [(196, 0.6), (300, 0.15)],
                 duration: 0.06, decay: 48, attack: 0.001),
            // medium: the classic tok
            tone(partials: [(196, 0.6), (300, 0.24), (470, 0.14)],
                 duration: 0.09, decay: 38, attack: 0.001),
            // hard: brighter, pitch-dropped, longer body
            tone(partials: [(185, 0.7), (300, 0.30), (470, 0.22), (760, 0.12)],
                 duration: 0.13, decay: 26, attack: 0.001),
        ]
    }

    /// Notes struck at onsets (seconds), each with partials given as (frequency multiple, amp)
    /// under its own attack/decay envelope, mixed into one buffer.
    private func notes(_ notes: [(Double, Double)],
                       partials: [(Double, Double)],
                       duration: Double,
                       decay: Double,
                       attack: Double) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(duration * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let out = buf.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            var v = 0.0
            for (f, onset) in notes where t >= onset {
                let lt = t - onset
                let env = min(lt / attack, 1.0) * exp(-decay * lt)
                for (mult, amp) in partials {
                    v += amp * env * sin(2.0 * .pi * f * mult * lt)
                }
            }
            out[i] = Float(v)
        }
        return buf
    }

    /// Sum sine partials under a fast-attack / exponential-decay envelope.
    private func tone(partials: [(Double, Double)],
                      duration: Double,
                      decay: Double,
                      attack: Double = 0.004) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(duration * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let out = buf.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            let env = min(t / attack, 1.0) * exp(-decay * t)
            var v = 0.0
            for (f, amp) in partials {
                v += amp * sin(2.0 * .pi * f * t)
            }
            out[i] = Float(v * env)
        }
        return buf
    }
}
