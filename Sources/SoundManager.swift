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
    private var configured = false

    // Pre-rendered buffers.
    private var blips: [AVAudioPCMBuffer] = []   // rising notes for +1/+2/+3
    private var chime: AVAudioPCMBuffer!         // the "big" sound for +4 and up
    private var bounceBuf: AVAudioPCMBuffer!     // wooden tok for a bounce

    private init() {
        renderBuffers()
        buildGraph()
    }

    // MARK: - Public API

    /// Play the score sound for a points gain. +1/+2/+3 play a soft rising pip
    /// that many times; a jump of +4 or more plays one mellow "done" note. Kept
    /// gentle on purpose — a quiet tick, not a slot-machine payout.
    func score(gained: Int) {
        guard GameSettings.shared.scoreSoundEnabled, gained > 0 else { return }
        if gained >= 4 {
            play(chime, volume: 0.4)
            return
        }
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

    /// Play the bounce "tok", volume scaled by impact speed (matches the haptic).
    func bounce(velocity: CGFloat) {
        guard GameSettings.shared.bounceSoundEnabled else { return }
        let speed = min(max(Float(abs(velocity)), 40), 1000)
        let t = (speed - 40) / (1000 - 40)          // 0...1
        play(bounceBuf, volume: 0.25 + 0.55 * t)    // 0.25 ... 0.80
    }

    /// Rebuild the audio session/engine when returning to the foreground; the
    /// system tears audio down on backgrounding.
    func restartIfNeeded() {
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
        if !configured {
            let session = AVAudioSession.sharedInstance()
            // .ambient => obeys the mute switch and mixes with other audio, which
            // is the right manners for a casual game's sound effects.
            try? session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setActive(true)
            configured = true
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
        // Rising major triad — C5, E5, G5. The first `gained` of these play for a
        // Soft rising pips for +1/+2/+3. Pure sines (no bright upper harmonic),
        // a warm mid register, and gentle whole-tone steps — so a streak nudges
        // upward rather than pinging like coins. Rounded attack, short decay.
        blips = [392.00, 440.00, 493.88].map { f in   // G4, A4, B4
            tone(partials: [(f, 0.8)], duration: 0.15, decay: 17, attack: 0.010)
        }
        // The "+4 or more" sound: a single mellow note (root + a quiet fifth for
        // warmth), same register as the pips so it reads as a soft resolution,
        // not a jackpot sparkle.
        chime = tone(partials: [(523.25, 0.7), (784.00, 0.18)],   // C5 + soft G5
                     duration: 0.42, decay: 9, attack: 0.010)
        // Wooden "tok": low, slightly inharmonic, very fast decay.
        bounceBuf = tone(partials: [(196, 0.6), (300, 0.24), (470, 0.14)],
                         duration: 0.09, decay: 38, attack: 0.001)
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
