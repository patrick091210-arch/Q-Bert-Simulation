import AVFoundation

final class EightBitMusicPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isRunning = false

    init() {
        setup()
    }

    private func setup() {
        let mainMixer = engine.mainMixerNode
        engine.attach(player)
        engine.connect(player, to: mainMixer, format: nil)

        do {
            try engine.start()
        } catch {
            print("Audio engine error: \(error)")
        }
    }

    func startLoop() {
        guard !isRunning else { return }
        isRunning = true
        scheduleLoop()
        player.play()
    }

    func stop() {
        guard isRunning else { return }
        player.stop()
        engine.reset()
        do {
            try engine.start()
        } catch {
            print("Audio engine restart error: \(error)")
        }
        isRunning = false
    }

    private func scheduleLoop() {
        let sampleRate: Double = 44100
        let duration: Double = 4
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = player.outputFormat(forBus: 0).standardizingSampleRate(sampleRate) else {
            return
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount

        let notes: [(frequency: Double, length: Double)] = [
            (293.66, 0.5),
            (329.63, 0.5),
            (392.00, 0.5),
            (440.00, 0.5),
            (392.00, 0.5),
            (329.63, 0.5),
            (293.66, 0.5),
            (246.94, 0.5)
        ]

        var sampleIndex: Int = 0
        let samples = buffer.floatChannelData![0]

        for note in notes {
            let samplesPerNote = Int(sampleRate * note.length)
            let period = sampleRate / note.frequency
            for i in 0..<samplesPerNote {
                let value: Float = (fmod(Double(i), period) / period) < 0.5 ? 0.7 : -0.7
                samples[sampleIndex] = value
                sampleIndex += 1
                if sampleIndex >= Int(frameCount) {
                    break
                }
            }
        }

        player.scheduleBuffer(buffer, at: nil, options: [.loops])
    }
}

private extension AVAudioFormat {
    func standardizingSampleRate(_ rate: Double) -> AVAudioFormat? {
        AVAudioFormat(commonFormat: commonFormat, sampleRate: rate, channels: channelCount, interleaved: isInterleaved)
    }
}
