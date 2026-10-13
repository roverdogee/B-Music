import AVFoundation
import Foundation

enum AudioCheckError: Error {
    case failed(String)
}

@main
struct BMusicAudioEngineChecks {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bmusic-engine-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stereoURL = directory.appendingPathComponent("stereo.wav")
        let monoURL = directory.appendingPathComponent("mono.wav")
        let compressedURL = directory.appendingPathComponent("compressed.m4a")
        try makeTone(at: stereoURL, sampleRate: 48_000, channels: 2)
        try makeTone(at: monoURL, sampleRate: 44_100, channels: 1)
        try makeTone(at: compressedURL, sampleRate: 44_100, channels: 2, compressed: true)

        let engine = AVAudioEngine()
        let core = BMusicAudioEngine(audioEngine: engine)
        var endedCount = 0
        core.onEnded = { endedCount += 1 }
        try core.load(url: stereoURL, volume: 1)
        try enableOfflineRendering(engine)
        try core.play()
        let original = try render(engine, seconds: 0.5)
        print("Checking progress and pause/resume")
        try check(original.contains { abs($0) > 0.01 }, "Output is silent")
        try check(abs(core.position - 0.5) < 0.03, "Progress does not follow rendered audio")

        core.pause()
        let pausedPosition = core.position
        try await Task.sleep(nanoseconds: 50_000_000)
        try check(!core.isPlaying && core.position == pausedPosition, "Pause did not freeze progress")
        try core.seek(to: 3)
        try check(!core.isPlaying && abs(core.position - 3) < 0.001, "Paused seek started playback")
        try core.play()
        _ = try render(engine, seconds: 0.25)
        try check(abs(core.position - 3.25) < 0.03, "Resume lost seek position")

        let beforeEQ = core.position
        print("Checking live EQ output")
        core.setEqualizer(gains: [-6, -6, -4, -2, 0, 0, 0, 0, 0, 0])
        try await Task.sleep(nanoseconds: 250_000_000)
        try check(core.isPlaying && core.position == beforeEQ, "EQ switch interrupted playback or reset progress")
        _ = try render(engine, seconds: 0.1)
        let equalized = try render(engine, seconds: 0.5)
        try check(amplitude(equalized, frequency: 64) < amplitude(original, frequency: 64) * 0.65,
                  "EQ did not attenuate the low-frequency signal")
        try check(amplitude(equalized, frequency: 4_000) > amplitude(original, frequency: 4_000) * 0.85,
                  "EQ unexpectedly attenuated the unchanged high-frequency band")

        try core.seek(to: 1)
        _ = try render(engine, seconds: 0.1)
        await Task.yield()
        try check(endedCount == 0, "Cancelled schedule emitted a stale end event")
        try check(abs(core.position - 1.1) < 0.03, "Playing seek used the old render offset")
        core.setEqualizer(gains: Array(repeating: 0, count: 10), animated: false)
        let reset = try render(engine, seconds: 0.5)
        try check(amplitude(reset, frequency: 64) > amplitude(original, frequency: 64) * 0.9,
                  "Disabling EQ did not restore the signal")

        core.pause()
        let beforeRebuild = core.position
        print("Checking engine recreation")
        try core.rebuild(recreateEngine: true, resume: false)
        try check(!core.isPlaying && abs(core.position - beforeRebuild) < 0.001,
                  "Engine recreation changed paused position")
        try enableOfflineRendering(core.audioEngine)
        try core.play()
        _ = try render(core.audioEngine, seconds: 0.25)
        try check(abs(core.position - beforeRebuild - 0.25) < 0.03,
                  "Recreated engine did not resume at the saved position")

        try core.load(url: monoURL, volume: 1, startPosition: 2)
        print("Checking mono conversion and end handling")
        try core.play()
        let mono = try render(core.audioEngine, seconds: 0.5)
        await Task.yield()
        try check(mono.contains { abs($0) > 0.01 }, "Mono / sample-rate conversion produced silence")
        try check(abs(core.position - 2.5) < 0.03, "Sample-rate conversion broke progress")
        try check(endedCount == 0, "Track change emitted the previous track's end event")
        _ = try render(core.audioEngine, seconds: core.duration - core.position + 0.1)
        try await Task.sleep(nanoseconds: 50_000_000)
        try check(endedCount == 1 && !core.isPlaying, "Natural completion did not finish exactly once")
        try core.play()
        _ = try render(core.audioEngine, seconds: 0.25)
        try core.seek(to: core.duration)
        try check(endedCount == 2 && !core.isPlaying, "Seeking to end did not finish exactly once")
        try core.play()
        _ = try render(core.audioEngine, seconds: 0.25)
        try check(core.position < 0.3, "Replay did not start at zero")
        try core.load(url: compressedURL, volume: 0.5, startPosition: 1)
        try core.play()
        let compressed = try render(core.audioEngine, seconds: 0.5)
        try check(compressed.contains { abs($0) > 0.01 }, "AAC cache playback is silent")
        try check(abs(core.position - 1.5) < 0.03, "AAC playback has incorrect progress")
        let quieterAmplitude = amplitude(compressed, frequency: 64)
        core.setVolume(1)
        let louder = try render(core.audioEngine, seconds: 0.5)
        try check(amplitude(louder, frequency: 64) > quieterAmplitude * 1.8, "Volume change did not apply during playback")
        core.stop()
        await Task.yield()
        try check(!core.hasAudio && core.position == 0 && endedCount == 2, "Stop left stale playback state")
        print("PASS: real audio output, live EQ/volume, AAC, pause/resume, seek, natural completion, stale callbacks, engine recreation and sample-rate conversion.")
    }

    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw AudioCheckError.failed(message) }
    }

    static func makeTone(at url: URL, sampleRate: Double, channels: AVAudioChannelCount, compressed: Bool = false) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let frameCount = AVAudioFrameCount(sampleRate * 8)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        for channel in 0..<Int(channels) {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<Int(frameCount) {
                let t = Double(frame) / sampleRate
                samples[frame] = Float(0.15 * sin(2 * .pi * 64 * t) + 0.15 * sin(2 * .pi * 4_000 * t))
            }
        }
        var settings = format.settings
        settings.removeValue(forKey: AVLinearPCMIsNonInterleaved)
        if compressed {
            settings = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
                        AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: 128_000]
        }
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    static func enableOfflineRendering(_ engine: AVAudioEngine) throws {
        engine.stop()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
    }

    static func render(_ engine: AVAudioEngine, seconds: Double) throws -> [Float] {
        let format = engine.manualRenderingFormat
        let totalFrames = Int(seconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        var samples: [Float] = []
        var retries = 0
        while samples.count < totalFrames {
            let frameCount = AVAudioFrameCount(min(1024, totalFrames - samples.count))
            switch try engine.renderOffline(frameCount, to: buffer) {
            case .success:
                samples.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
                retries = 0
            case .cannotDoInCurrentContext, .insufficientDataFromInputNode:
                retries += 1
                try check(retries < 100, "Offline rendering made no progress")
            case .error:
                throw AudioCheckError.failed("Audio engine reported a render error")
            @unknown default:
                throw AudioCheckError.failed("Unknown render status")
            }
        }
        return samples
    }

    static func amplitude(_ samples: [Float], frequency: Double) -> Double {
        var real = 0.0
        var imaginary = 0.0
        for (index, sample) in samples.enumerated() {
            let phase = 2 * .pi * frequency * Double(index) / 48_000
            real += Double(sample) * cos(phase)
            imaginary += Double(sample) * sin(phase)
        }
        return 2 * sqrt(real * real + imaginary * imaginary) / Double(samples.count)
    }
}
