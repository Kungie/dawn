import AppKit
import Foundation

/// A short, spacey "ping" made in code, so no sound files ship with the app: a bright tone that glides
/// down onto C6 with a fifth above it, then fades out through a darkening echo, like a sonar in space.
enum SpacePing {
    private static var current: NSSound?

    static func play() {
        guard let sound = NSSound(data: wav) else { return }
        sound.volume = 0.8
        current = sound
        sound.play()
    }

    static let wav: Data = render()

    private static func render() -> Data {
        let rate = 44_100.0
        let length = Int(rate * 2.2)
        var dry = [Double](repeating: 0, count: length)

        // Two voices: the root and a softer fifth that comes in 60 ms later.
        func voice(base: Double, delay: Double, gain: Double) {
            var phase = 0.0
            let start = Int(delay * rate)
            for i in 0..<Int(rate * 0.9) where start + i < length {
                let t = Double(i) / rate
                let freq = base * (1 + 0.45 * exp(-t * 22))          // fast downward glide
                let vibrato = 1 + 0.004 * sin(2 * .pi * 6.5 * t)       // a little shimmer
                phase += 2 * .pi * freq * vibrato / rate
                let env = (1 - exp(-t * 600)) * exp(-t * 5.5)          // click-free attack, long tail
                let tone = sin(phase) + 0.28 * sin(2.003 * phase) + 0.08 * sin(3.01 * phase)
                dry[start + i] += gain * env * tone
            }
        }
        voice(base: 1046.5, delay: 0, gain: 1.0)     // C6
        voice(base: 1568.0, delay: 0.06, gain: 0.42) // G6

        // Feedback echo with a one-pole low-pass in the loop, so every repeat is darker than the last.
        let delay = Int(rate * 0.19)
        var out = dry
        var lp = 0.0
        for i in delay..<length {
            lp += 0.35 * (out[i - delay] - lp)
            out[i] += 0.5 * lp
        }

        let peak = out.map(abs).max() ?? 1
        let samples = out.map { Int16(max(-1, min(1, $0 / peak * 0.7)) * 32_767) }

        var data = Data()
        func put<T: FixedWidthInteger>(_ v: T) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate * 2)); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(UInt32(bytes))
        for s in samples { put(s) }
        return data
    }
}
