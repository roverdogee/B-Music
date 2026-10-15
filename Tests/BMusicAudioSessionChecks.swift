import AVFoundation
import Foundation

@main
struct BMusicAudioSessionChecks {
    @MainActor
    static func main() async throws {
        let manager = FileManager.default
        let directory = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BMusicAudio")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let indexURL = directory.appendingPathComponent("index.json")
        let oldData = try? Data(contentsOf: indexURL)
        var entries = oldData.flatMap { try? JSONDecoder().decode([String: BMusicAudioCacheEntry].self, from: $0) } ?? [:]
        let originalIDs = Set(entries.keys)
        let id = "session-check-\(UUID().uuidString)"
        let secondID = "\(id)-second"
        let fileName = "\(id).m4a"
        try makeQuietAudio(at: directory.appendingPathComponent(fileName))
        entries[id] = BMusicAudioCacheEntry(id: id, fileName: fileName, lastAccessed: Date())
        entries[secondID] = BMusicAudioCacheEntry(id: secondID, fileName: fileName, lastAccessed: Date())
        try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)

        var states: [[String: Any]] = []
        var progress: [[String: Any]] = []
        var loadingRoute: AVAudioSession.RouteChangeReason?
        let native = NativeAudioPlayer { event, payload in
            if event == "native-audio-state" { states.append(payload) }
            if event == "native-audio-progress" { progress.append(payload) }
            if event == "native-audio-state", payload["state"] as? String == "loading", let reason = loadingRoute {
                loadingRoute = nil
                postRoute(reason)
            }
        }
        native.setVolumeBalancingEnabled(false)
        do {
            let cached = try await native.playCached(cacheID: id, title: "First", artist: "Test", artworkURL: nil)
            try check(cached, "Could not open seeded AAC cache")
            try check(AVAudioSession.sharedInstance().category == .playback
                      && AVAudioSession.sharedInstance().routeSharingPolicy == .longFormAudio,
                      "Music playback is not configured for the shared long-form audio / AirPlay route")
            try await wait(700)
            _ = native.pause()
            try check((progress.last?["position"] as? Double ?? 0) > 0.4, "iOS playback did not advance")
            _ = native.seek(seconds: 2)
            try check(abs((progress.last?["position"] as? Double ?? 0) - 2) < 0.01, "Paused seek lost its position")
            _ = native.resume()
            native.setEqualizerPreset(.airPods)
            try await wait(250)

            postInterruption(.began)
            try await wait(100)
            try check(states.last?["state"] as? String == "paused", "Interruption did not pause playback")
            let interruptedAt = states.last?["position"] as? Double ?? 0
            postInterruption(.ended, shouldResume: true)
            try await wait(500)
            try check(states.last?["state"] as? String == "playing", "Allowed interruption recovery did not resume")
            _ = native.pause()
            let resumedAt = progress.last?["position"] as? Double ?? 0
            try check(resumedAt >= interruptedAt && resumedAt < interruptedAt + 1, "Interruption recovery reset progress")

            _ = native.resume()
            postInterruption(.began)
            try await wait(100)
            _ = native.pause()
            postInterruption(.ended, shouldResume: true)
            try await wait(400)
            try check(states.last?["state"] as? String == "paused", "Interruption overrode a user's pause")

            let pausedStateCount = states.count
            NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
                userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue])
            try await wait(300)
            try check(states.count == pausedStateCount, "A paused route change reactivated the audio session")

            _ = native.resume()
            NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
                userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
            try await wait(150)
            try check(states.last?["state"] as? String == "paused", "Headphone disconnection did not pause")
            _ = native.resume()

            postInterruption(.began)
            try await wait(100)
            NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
                userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
            try await wait(150)
            let detachedPosition = progress.last?["position"] as? Double ?? 0
            _ = native.resume()
            try await wait(350)
            try check(states.last?["state"] as? String == "playing", "Resume remained blocked after detachment without an interruption-ended notification")
            _ = native.pause()
            try check((progress.last?["position"] as? Double ?? 0) > detachedPosition + 0.1,
                      "Resume reported playing but audio did not advance after detachment")
            _ = native.resume()

            postInterruption(.began)
            try await wait(100)
            NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
                userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
            try await wait(100)
            _ = try await native.playCached(cacheID: secondID, title: "After detach", artist: "Test", artworkURL: nil, startPosition: 1)
            try await wait(250)
            try check(states.last?["state"] as? String == "playing", "Track change remained blocked after detachment")
            _ = native.pause()
            try check((progress.last?["position"] as? Double ?? 0) > 1.1, "Track change reported playback without advancing audio")
            _ = native.resume()
            postInterruption(.ended, shouldResume: false)
            try await wait(150)
            try check(states.last?["state"] as? String == "playing", "A late interruption-ended notification paused explicitly resumed playback")
            let beforeReset = progress.last?["position"] as? Double ?? resumedAt
            NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
            NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
                userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue])
            try await wait(500)
            try check(states.last?["state"] as? String == "playing", "Audio services reset did not recreate a playing engine")
            _ = native.pause()
            try check((progress.last?["position"] as? Double ?? 0) >= beforeReset, "Audio services reset lost progress")

            let first = Task { @MainActor in
                try await native.playCached(cacheID: id, title: "First", artist: "Test", artworkURL: nil)
            }
            let second = Task { @MainActor in
                try await native.playCached(cacheID: secondID, title: "Second", artist: "Test", artworkURL: nil)
            }
            do { _ = try await first.value } catch is CancellationError {}
            _ = try await second.value
            try await wait(200)
            _ = native.pause()
            try check(states.last?["title"] as? String == "Second", "An old request replaced the latest song")
            try check(!states.contains { $0["state"] as? String == "ended" }, "A cancelled schedule emitted an end event")

            // Route notifications use the same transport-independent path for wired and Bluetooth outputs.
            for reason in [AVAudioSession.RouteChangeReason.newDeviceAvailable, .override, .routeConfigurationChange, .wakeFromSleep, .unknown] {
                _ = try await native.playCached(cacheID: id, title: "Route switch", artist: "Test", artworkURL: nil, startPosition: 1)
                postRoute(reason)
                try await wait(550)
                try check(states.last?["state"] as? String == "playing", "Output switch did not resume: \(reason)")
                _ = native.pause()
                try check((progress.last?["position"] as? Double ?? 0) > 1.15, "Output switch did not advance audio: \(reason)")
            }

            _ = native.resume()
            postRoute(.newDeviceAvailable)
            postRoute(.override)
            postRoute(.routeConfigurationChange)
            try await wait(550)
            try check(states.last?["state"] as? String == "playing", "A burst of output changes stranded playback")

            postRoute(.newDeviceAvailable)
            try await wait(25)
            _ = native.pause()
            let pauseIndex = states.count
            postRoute(.routeConfigurationChange)
            try await wait(450)
            try check(!states.dropFirst(pauseIndex).contains { $0["state"] as? String == "playing" },
                      "Pending output recovery overrode manual pause")

            postRoute(.oldDeviceUnavailable)
            postRoute(.newDeviceAvailable)
            try await wait(350)
            try check(states.last?["state"] as? String == "paused", "Reconnect automatically played after disconnection")
            _ = native.resume()
            try await wait(250)
            try check(states.last?["state"] as? String == "playing", "Manual resume failed after disconnect/reconnect")

            postRoute(.oldDeviceUnavailable)
            postInterruption(.began)
            try await wait(150)
            _ = native.resume()
            try await wait(250)
            try check(states.last?["state"] as? String == "playing", "Reversed disconnect/interruption order stranded playback")
            _ = native.pause()
            postInterruption(.ended, shouldResume: true)
            try await wait(250)
            try check(states.last?["state"] as? String == "paused", "Late interruption hint overrode pause after route switching")

            _ = native.resume()
            postRoute(.newDeviceAvailable)
            try await wait(25)
            _ = try await native.playCached(cacheID: secondID, title: "New song during switch", artist: "Test", artworkURL: nil)
            try await wait(450)
            _ = native.pause()
            try check(states.last?["title"] as? String == "New song during switch", "Old output recovery restored the previous song")
            try check((progress.last?["position"] as? Double ?? 0) > 0.2, "Song change during output switch did not advance")

            native.setVolumeBalancingEnabled(true)
            for reason in [AVAudioSession.RouteChangeReason.newDeviceAvailable, .oldDeviceUnavailable] {
                loadingRoute = reason
                _ = try await native.playCached(cacheID: id, title: "Loading switch", artist: "Test", artworkURL: nil)
                try await wait(550)
                try check(loadingRoute == nil, "Loading notification did not inject the output change")
                let expected = reason == .oldDeviceUnavailable ? "paused" : "playing"
                try check(states.last?["state"] as? String == expected, "Unexpected state after output change during preparation: \(reason)")
                _ = native.resume()
                try await wait(250)
                _ = native.pause()
                try check((progress.last?["position"] as? Double ?? 0) > 0.1, "Prepared song could not resume after output change")
            }

            _ = native.resume()
            postRoute(.noSuitableRouteForCategory)
            try await wait(250)
            try check(states.last?["state"] as? String == "paused", "Missing output route was reported as playing")
            postRoute(.newDeviceAvailable)
            postRoute(.routeConfigurationChange)
            try await wait(350)
            try check(states.last?["state"] as? String == "paused", "Available route unexpectedly overrode pause after output loss")
            _ = native.resume()
            try await wait(350)
            try check(states.last?["state"] as? String == "playing", "Playback could not restart when an output became available")
            _ = native.pause()
            try check((progress.last?["position"] as? Double ?? 0) > 0.2, "Recovered output did not advance audio")
            _ = native.stop()
            await BMusicAudioCache.shared.clear(keeping: originalIDs)
            print("PASS: AAC/EQ, shared AirPlay policy, output switching/wake/loss, wired/Bluetooth notifications, pause/reconnect, loading/song changes, interruptions, media reset and rapid track changes.")
        } catch {
            _ = native.stop()
            await BMusicAudioCache.shared.clear(keeping: originalIDs)
            throw error
        }
    }

    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "BMusicAudioSessionChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func wait(_ milliseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    static func postInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool = false) {
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: [
            AVAudioSessionInterruptionTypeKey: type.rawValue,
            AVAudioSessionInterruptionOptionKey: shouldResume ? AVAudioSession.InterruptionOptions.shouldResume.rawValue : 0
        ])
    }

    static func postRoute(_ reason: AVAudioSession.RouteChangeReason) {
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue])
    }

    static func makeQuietAudio(at url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480_000)!
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            for frame in 0..<Int(buffer.frameLength) {
                buffer.floatChannelData![channel][frame] = Float(0.000_001 * sin(2 * .pi * 440 * Double(frame) / 48_000))
            }
        }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }
}
