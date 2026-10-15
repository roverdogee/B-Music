import AVFoundation
import Foundation

@MainActor
final class BMusicAudioEngine {
    private(set) var audioEngine: AVAudioEngine
    private var playerNode = AVAudioPlayerNode()
    private var equalizer = AVAudioUnitEQ(numberOfBands: 10)
    private var audioFile: AVAudioFile?
    private var sourceURL: URL?
    private var scheduledStartFrame: AVAudioFramePosition = 0
    private var lastKnownPosition: Double = 0
    private var scheduleID = UUID()
    private var equalizerTask: Task<Void, Never>?
    private var targetGains: [Float] = Array(repeating: 0, count: 10)
    private var playbackVolume: Float = 1
    private(set) var isPlaying = false
    var onEnded: (() -> Void)?
    var onFailure: ((Error) -> Void)?

    init(audioEngine: AVAudioEngine = AVAudioEngine()) {
        self.audioEngine = audioEngine
        attachNodes()
    }

    var hasAudio: Bool { audioFile != nil }

    var duration: Double {
        guard let audioFile else { return 0 }
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }

    var position: Double {
        if isPlaying,
           let time = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: time),
           playerTime.sampleRate > 0,
           let audioFile {
            let start = Double(scheduledStartFrame) / audioFile.processingFormat.sampleRate
            let renderedPosition = start + Double(playerTime.sampleTime) / playerTime.sampleRate
            lastKnownPosition = min(duration, max(lastKnownPosition, renderedPosition))
        }
        return lastKnownPosition
    }

    func load(url: URL, volume: Float, startPosition: Double = 0) throws {
        stop()
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.processingFormat.sampleRate > 0,
              file.processingFormat.channelCount > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        audioFile = file
        sourceURL = url
        playbackVolume = volume
        lastKnownPosition = clampedPosition(startPosition)
        try configureGraph(format: file.processingFormat)
    }

    func setVolume(_ volume: Float) {
        playbackVolume = min(1, max(0, volume))
        playerNode.volume = playbackVolume
    }

    func setEqualizer(gains: [Float], animated: Bool = true) {
        guard gains.count == equalizer.bands.count else { return }
        targetGains = gains
        equalizerTask?.cancel()
        let initialGains = equalizer.bands.map(\.gain)
        let initialGlobalGain = equalizer.globalGain
        // Leave headroom for boosted bands to avoid clipping the output.
        let globalGain = -max(0, gains.max() ?? 0)
        guard animated, isPlaying else {
            applyGains(gains, globalGain: globalGain)
            return
        }
        equalizerTask = Task { [weak self] in
            for step in 1...12 {
                guard !Task.isCancelled, let self else { return }
                let fraction = Float(step) / 12
                let interpolated = zip(initialGains, gains).map { start, end in
                    start + (end - start) * fraction
                }
                self.applyGains(interpolated, globalGain: initialGlobalGain + (globalGain - initialGlobalGain) * fraction)
                do {
                    try await Task.sleep(nanoseconds: 15_000_000)
                } catch { return }
            }
        }
    }

    func play() throws {
        guard let file = audioFile else { return }
        if isPlaying && audioEngine.isRunning && playerNode.isPlaying { return }
        if isPlaying { pause() }
        let frame = AVAudioFramePosition(clampedPosition(lastKnownPosition) * file.processingFormat.sampleRate)
        // Resuming at the end starts the song again; seeking to the end still ends it.
        try schedule(from: frame >= file.length ? 0 : frame)
    }

    func pause() {
        lastKnownPosition = position
        scheduleID = UUID()
        isPlaying = false
        playerNode.stop()
        audioEngine.pause()
    }

    func suspendOutput() {
        pause()
        audioEngine.stop()
        audioEngine.reset()
    }

    var outputDiagnostics: String {
        let hardware = audioEngine.outputNode.outputFormat(forBus: 0)
        let mixer = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        return "hardware=\(hardware.sampleRate)Hz/\(hardware.channelCount)ch mixer=\(mixer.sampleRate)Hz/\(mixer.channelCount)ch running=\(audioEngine.isRunning) playerGain=\(playerNode.volume) mixerGain=\(audioEngine.mainMixerNode.outputVolume)"
    }

    func seek(to seconds: Double) throws {
        guard let file = audioFile else { return }
        let wasPlaying = isPlaying
        pause()
        lastKnownPosition = clampedPosition(seconds)
        if wasPlaying {
            let frame = AVAudioFramePosition(lastKnownPosition * file.processingFormat.sampleRate)
            if frame >= file.length {
                lastKnownPosition = duration
                onEnded?()
            } else {
                try schedule(from: frame)
            }
        }
    }

    func stop() {
        scheduleID = UUID()
        isPlaying = false
        playerNode.stop()
        audioEngine.stop()
        audioEngine.reset()
        audioFile = nil
        sourceURL = nil
        lastKnownPosition = 0
        scheduledStartFrame = 0
    }

    func rebuild(recreateEngine: Bool = false, resume: Bool) throws {
        let savedPosition = position
        pause()
        audioEngine.stop()
        if recreateEngine {
            audioEngine = AVAudioEngine()
            playerNode = AVAudioPlayerNode()
            equalizer = AVAudioUnitEQ(numberOfBands: 10)
            attachNodes()
        }
        guard let sourceURL else { return }
        let file = try AVAudioFile(forReading: sourceURL)
        audioFile = file
        lastKnownPosition = clampedPosition(savedPosition)
        try configureGraph(format: file.processingFormat)
        if resume { try play() }
    }

    private func attachNodes() {
        audioEngine.attach(playerNode)
        audioEngine.attach(equalizer)
    }

    private func configureGraph(format: AVAudioFormat) throws {
        equalizerTask?.cancel()
        audioEngine.disconnectNodeOutput(playerNode)
        audioEngine.disconnectNodeOutput(equalizer)
        audioEngine.connect(playerNode, to: equalizer, format: format)
        audioEngine.connect(equalizer, to: audioEngine.mainMixerNode, format: format)
        if !audioEngine.isInManualRenderingMode {
            let output = audioEngine.outputNode
            let hardware = output.outputFormat(forBus: 0)
            guard hardware.sampleRate > 0, hardware.channelCount > 0 else {
                throw NSError(domain: "BMusicAudioEngine", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "音频输出设备暂不可用，请稍后重试。"])
            }
            audioEngine.disconnectNodeOutput(audioEngine.mainMixerNode)
            audioEngine.connect(audioEngine.mainMixerNode, to: output, format: hardware)
        }
        let frequencies: [Float] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
        for (index, frequency) in frequencies.enumerated() {
            let band = equalizer.bands[index]
            band.filterType = .parametric
            band.frequency = min(frequency, Float(format.sampleRate * 0.45))
            band.bandwidth = 0.5
            band.bypass = Double(frequency) >= format.sampleRate * 0.5
        }
        applyGains(targetGains, globalGain: -max(0, targetGains.max() ?? 0))
        playerNode.volume = playbackVolume
        audioEngine.prepare()
    }

    private func applyGains(_ gains: [Float], globalGain: Float) {
        for (band, gain) in zip(equalizer.bands, gains) { band.gain = gain }
        equalizer.globalGain = globalGain
        equalizer.bypass = globalGain == 0 && gains.allSatisfy { $0 == 0 }
    }

    private func clampedPosition(_ seconds: Double) -> Double {
        seconds.isFinite ? min(duration, max(0, seconds)) : 0
    }

    private func schedule(from frame: AVAudioFramePosition) throws {
        guard let file = audioFile, frame < file.length else { return }
        scheduleID = UUID()
        let token = scheduleID
        playerNode.stop()
        scheduledStartFrame = max(0, frame)
        lastKnownPosition = Double(scheduledStartFrame) / file.processingFormat.sampleRate
        let frameCount = AVAudioFrameCount(min(Int64(UInt32.max), file.length - scheduledStartFrame))
        let endFrame = scheduledStartFrame + Int64(frameCount)
        playerNode.scheduleSegment(
            file, startingFrame: scheduledStartFrame, frameCount: frameCount, at: nil,
            completionCallbackType: audioEngine.isInManualRenderingMode ? .dataRendered : .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.scheduleID == token, self.isPlaying else { return }
                if endFrame < file.length {
                    do { try self.schedule(from: endFrame) }
                    catch {
                        self.pause()
                        self.onFailure?(error)
                    }
                } else {
                    self.isPlaying = false
                    self.lastKnownPosition = self.duration
                    self.audioEngine.pause()
                    self.onEnded?()
                }
            }
        }
        if !audioEngine.isRunning { try audioEngine.start() }
        isPlaying = true
        playerNode.play()
    }
}
