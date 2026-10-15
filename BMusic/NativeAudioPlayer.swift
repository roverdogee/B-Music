import AVFoundation
import Foundation
import MediaPlayer
import UIKit

enum BMusicEqualizerPreset: String, CaseIterable, Identifiable, Codable {
    case off
    case acoustic
    case bassBooster
    case bassReducer
    case classical
    case dance
    case deep
    case electronic
    case flat
    case hipHop
    case jazz
    case latin
    case loudness
    case airPods
    case carAudio
    case carClear
    case piano
    case pop
    case rhythmAndBlues
    case rock
    case smallSpeakers
    case spokenWord
    case trebleBooster
    case trebleReducer
    case vocalBooster

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关闭"
        case .acoustic: return "Acoustic"
        case .bassBooster: return "Bass Booster"
        case .bassReducer: return "Bass Reducer"
        case .classical: return "Classical"
        case .dance: return "Dance"
        case .deep: return "Deep"
        case .electronic: return "Electronic"
        case .flat: return "Flat"
        case .hipHop: return "Hip-Hop"
        case .jazz: return "Jazz"
        case .latin: return "Latin"
        case .loudness: return "Loudness"
        case .airPods: return "AirPods"
        case .carAudio: return "车载音响"
        case .carClear: return "车载清晰"
        case .piano: return "Piano"
        case .pop: return "Pop"
        case .rhythmAndBlues: return "R&B"
        case .rock: return "Rock"
        case .smallSpeakers: return "Small Speakers"
        case .spokenWord: return "Spoken Word"
        case .trebleBooster: return "Treble Booster"
        case .trebleReducer: return "Treble Reducer"
        case .vocalBooster: return "Vocal Booster"
        }
    }

    var bandGains: [Float] {
        switch self {
        case .off, .flat:
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .acoustic:
            return [4, 3, 2, 1, 1, 2, 3, 4, 4, 3]
        case .bassBooster:
            return [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]
        case .bassReducer:
            return [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0]
        case .classical:
            return [4, 3, 2, 0, 0, 0, 1, 2, 3, 4]
        case .dance:
            return [5, 4, 2, 0, 0, -1, -1, 2, 4, 5]
        case .deep:
            return [5, 4, 3, 1, -1, -2, -1, 1, 3, 4]
        case .electronic:
            return [4, 3, 1, 0, -1, 1, 2, 3, 4, 4]
        case .hipHop:
            return [5, 4, 2, 1, -1, -1, 1, 2, 3, 4]
        case .jazz:
            return [3, 2, 1, 1, -1, -1, 0, 1, 2, 3]
        case .latin:
            return [4, 3, 1, 0, -1, -1, 0, 2, 3, 4]
        case .loudness:
            return [6, 5, 3, 1, 0, 0, 1, 3, 5, 6]
        case .airPods:
            return [2, 2, 1, 0, 1, 1, 1, 0, -1, -1]
        case .carAudio:
            return [-2, -1, 1, 1, 0, 1, 2, 2, 1, 0]
        case .carClear:
            return [-3, -1, 2, 1, 1, 2, 3, 2, 1, 0]
        case .piano:
            return [2, 1, 0, 1, 2, 2, 1, 0, 1, 2]
        case .pop:
            return [-1, 2, 4, 4, 2, 0, -1, -1, -1, -1]
        case .rhythmAndBlues:
            return [4, 3, 2, 1, -1, -1, 1, 2, 3, 4]
        case .rock:
            return [5, 4, 3, 1, -1, -1, 1, 3, 4, 5]
        case .smallSpeakers:
            return [-2, -1, 0, 2, 3, 3, 2, 1, 0, -1]
        case .spokenWord:
            return [-3, -2, -1, 2, 4, 4, 3, 1, -1, -2]
        case .trebleBooster:
            return [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]
        case .trebleReducer:
            return [0, 0, 0, 0, 0, -1, -2, -4, -5, -6]
        case .vocalBooster:
            return [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]
        }
    }
}

enum NativeAudioError: LocalizedError {
    case invalidURL
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid audio URL"
        case .downloadFailed(let message):
            return message
        }
    }
}

@MainActor
final class NativeAudioPlayer {
    private let core = BMusicAudioEngine()
    private var currentTitle = ""
    private var currentArtist = ""
    private var currentArtwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var temporaryAudioURL: URL?
    private var currentAudioURL: URL?
    private var playbackRequestID = UUID()
    private var volumeBalancingEnabled = true
    private var equalizerPreset: BMusicEqualizerPreset = .off
    private var balancedVolumes: [String: Float] = [:]
    private var wantsPlayback = false
    private var isInterrupted = false
    private var interruptionGeneration = 0
    private var playbackInterruptionGeneration = 0
    private var resumeAfterInterruption = false
    private var isRebuilding = false
    private var needsEngineRecreation = false
    private var needsGraphRecovery = false
    private var needsSessionReset = false
    private var progressTimer: Timer?
    private var sessionObservers: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private nonisolated static let managedTemporaryAudioPrefix = "eno-audio-"
    private nonisolated static let systemDownloadTemporaryPrefix = "CFNetworkDownload"
    private nonisolated static let staleSystemDownloadAge: TimeInterval = 300
    private let sendEvent: (String, [String: Any]) -> Void

    init(sendEvent: @escaping (String, [String: Any]) -> Void = { _, _ in }) {
        self.sendEvent = sendEvent
        Self.removeStaleTemporaryAudio()
        core.onEnded = { [weak self] in
            guard let self else { return }
            self.wantsPlayback = false
            self.stopProgressTimer()
            self.sendProgress()
            self.updateNowPlaying()
            self.sendState("ended")
        }
        core.onFailure = { [weak self] error in
            self?.sendState("failed", message: error.localizedDescription)
        }
        configureSessionObservers()
        configureRemoteCommands()
    }

    func setVolumeBalancingEnabled(_ enabled: Bool) {
        volumeBalancingEnabled = enabled
        volumeTask?.cancel()
        guard enabled, let url = currentAudioURL else {
            core.setVolume(1)
            return
        }
        let requestID = playbackRequestID
        volumeTask = Task { [weak self] in
            guard let self else { return }
            let volume = await self.playbackVolume(for: url, requestID: requestID)
            guard !Task.isCancelled, self.isCurrentPlaybackRequest(requestID) else { return }
            self.core.setVolume(volume)
        }
    }

    func setEqualizerPreset(_ preset: BMusicEqualizerPreset) {
        equalizerPreset = preset
        core.setEqualizer(gains: preset.bandGains)
    }

    func playCached(cacheID: String, title: String?, artist: String?, artworkURL: String?, startPosition: Double = 0, legacyCacheID: String? = nil) async throws -> Bool {
        let requestID = beginPlayback(title: title, artist: artist, artworkURL: artworkURL)
        let localURL = await BMusicAudioCache.shared.cachedURL(for: cacheID, legacyID: legacyCacheID)
        try checkRequest(requestID)
        guard let localURL else { return false }
        sendState("loading", message: "正在读取缓存...")
        try await prepareAudio(at: localURL, startPosition: startPosition, requestID: requestID)
        return true
    }

    func play(url: String, title: String?, artist: String?, artworkURL: String?, cookie: String = "", cacheID: String? = nil, startPosition: Double = 0) async throws -> Any {
        guard let audioURL = URL(string: url) else { throw NativeAudioError.invalidURL }
        let requestID = beginPlayback(title: title, artist: artist, artworkURL: artworkURL)
        sendState("loading", message: "正在准备音频...")
        let localURL: URL
        do {
            if let cacheID {
                localURL = try await BMusicAudioCache.shared.audioURL(
                    for: cacheID, sourceURL: audioURL, cookie: cookie,
                    cancelingActivePlaybackDownload: true
                )
            } else {
                localURL = try await downloadTemporaryAudio(from: audioURL, cookie: cookie)
            }
        } catch {
            try checkRequest(requestID)
            throw error
        }
        guard isCurrentPlaybackRequest(requestID) else {
            if cacheID == nil { try? FileManager.default.removeItem(at: localURL) }
            throw CancellationError()
        }
        if cacheID == nil { temporaryAudioURL = localURL }
        try await prepareAudio(at: localURL, startPosition: startPosition, requestID: requestID)
        return ["success": true, "title": title ?? "", "artist": artist ?? ""]
    }

    func pause() -> Any {
        wantsPlayback = false
        resumeAfterInterruption = false
        recoveryTask?.cancel()
        core.pause()
        stopProgressTimer()
        sendProgress()
        updateNowPlaying()
        sendState("paused")
        return ["success": true]
    }

    func resume() -> Any {
        wantsPlayback = true
        do {
            recoveryTask?.cancel()
            playbackInterruptionGeneration = interruptionGeneration
            if isInterrupted { needsEngineRecreation = true }
            try activateSession()
            guard core.hasAudio else { return ["success": true] }
            if needsGraphRecovery || needsEngineRecreation {
                try core.rebuild(recreateEngine: needsEngineRecreation, resume: false)
                needsEngineRecreation = false
                needsGraphRecovery = false
            }
            try startCorePlayback()
            startProgressTimer()
            updateNowPlaying()
            sendState("playing")
            return ["success": true]
        } catch {
            sendState("failed", message: error.localizedDescription)
            return ["success": false]
        }
    }

    func stop() -> Any {
        playbackRequestID = UUID()
        artworkTask?.cancel()
        volumeTask?.cancel()
        recoveryTask?.cancel()
        wantsPlayback = false
        resumeAfterInterruption = false
        core.stop()
        stopProgressTimer()
        currentAudioURL = nil
        currentArtwork = nil
        removeTemporaryAudio()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        sendState("stopped")
        return ["success": true]
    }

    func seek(seconds: Double) -> Any {
        guard core.hasAudio else { return ["success": false] }
        do {
            try core.seek(to: seconds)
            sendProgress()
            updateNowPlaying()
            return ["success": true, "position": core.position]
        } catch {
            sendState("failed", message: error.localizedDescription)
            return ["success": false]
        }
    }

    private func beginPlayback(title: String?, artist: String?, artworkURL: String?) -> UUID {
        playbackRequestID = UUID()
        artworkTask?.cancel()
        volumeTask?.cancel()
        recoveryTask?.cancel()
        core.stop()
        stopProgressTimer()
        removeTemporaryAudio()
        currentAudioURL = nil
        currentArtwork = nil
        currentTitle = title ?? ""
        currentArtist = artist ?? ""
        wantsPlayback = true
        playbackInterruptionGeneration = interruptionGeneration
        if isInterrupted { needsEngineRecreation = true }
        resumeAfterInterruption = isInterrupted
        loadArtwork(from: artworkURL)
        updateNowPlaying()
        return playbackRequestID
    }

    private func prepareAudio(at url: URL, startPosition: Double, requestID: UUID) async throws {
        let volume = await playbackVolume(for: url, requestID: requestID)
        try checkRequest(requestID)
        if !isInterrupted || playbackInterruptionGeneration == interruptionGeneration { try activateSession() }
        if needsEngineRecreation {
            try core.rebuild(recreateEngine: true, resume: false)
            needsEngineRecreation = false
        }
        currentAudioURL = url
        try core.load(url: url, volume: volume, startPosition: startPosition)
        needsGraphRecovery = false
        core.setEqualizer(gains: equalizerPreset.bandGains, animated: false)
        sendState("ready")
        if wantsPlayback && !isInterrupted {
            try startCorePlayback()
            startProgressTimer()
            sendState("playing")
        } else {
            sendState("paused")
        }
        sendProgress()
        updateNowPlaying()
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        if needsSessionReset {
            logAudioRoute("before session reset")
            stopProgressTimer()
            core.suspendOutput()
            do {
                try session.setActive(false)
            } catch {
                let failure = error as NSError
                guard failure.domain == NSOSStatusErrorDomain,
                      failure.code == AVAudioSession.ErrorCode.isBusy.rawValue else { throw error }
            }
            needsEngineRecreation = true
            needsGraphRecovery = true
        }
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        try session.setActive(true)
        needsSessionReset = false
        logAudioRoute("session activated")
        // User-initiated activation can succeed without an interruption-ended notification.
        isInterrupted = false
        resumeAfterInterruption = false
    }

    private func startCorePlayback() throws {
        do {
            try core.play()
        } catch {
            needsEngineRecreation = true
            needsGraphRecovery = true
            try core.rebuild(recreateEngine: true, resume: false)
            try core.play()
            needsEngineRecreation = false
            needsGraphRecovery = false
        }
        logAudioRoute("playback output started")
    }

    private func logAudioRoute(_ stage: String) {
        #if DEBUG
        let session = AVAudioSession.sharedInstance()
        let ports = session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        print("[BMusicAudio] \(stage): route=[\(ports)] volume=\(session.outputVolume) \(core.outputDiagnostics)")
        #endif
    }

    private func isCurrentPlaybackRequest(_ requestID: UUID) -> Bool {
        playbackRequestID == requestID
    }

    private func checkRequest(_ requestID: UUID) throws {
        guard isCurrentPlaybackRequest(requestID), !Task.isCancelled else {
            throw CancellationError()
        }
    }

    private func playbackVolume(for url: URL, requestID: UUID) async -> Float {
        guard volumeBalancingEnabled else {
            return 1
        }

        let cacheKey = url.path
        if let cached = balancedVolumes[cacheKey] {
            return cached
        }

        let measuredDB = await Task.detached(priority: .userInitiated) {
            Self.estimateLoudnessDB(for: url)
        }.value
        guard isCurrentPlaybackRequest(requestID), volumeBalancingEnabled else {
            return 1
        }

        let volume = Self.balancedPlaybackVolume(measuredDB: measuredDB)
        balancedVolumes[cacheKey] = volume
        return volume
    }

    private nonisolated static func estimateLoudnessDB(for url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else {
            return nil
        }

        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, file.length > 0 else {
            return nil
        }

        let windowFrames = AVAudioFrameCount(min(sampleRate * 0.4, Double(UInt32.max)))
        guard windowFrames > 0 else {
            return nil
        }

        let windowCount = 9
        let maximumStart = max(0, file.length - AVAudioFramePosition(windowFrames))
        var windowEnergies: [Double] = []

        for index in 0..<windowCount {
            let fraction = Double(index + 1) / Double(windowCount + 1)
            file.framePosition = AVAudioFramePosition(Double(maximumStart) * fraction)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: windowFrames) else {
                continue
            }

            do {
                try file.read(into: buffer, frameCount: windowFrames)
            } catch {
                continue
            }

            guard buffer.frameLength > 0,
                  let channels = buffer.floatChannelData
            else {
                continue
            }

            var sumSquares = 0.0
            let frameLength = Int(buffer.frameLength)
            let channelCount = Int(format.channelCount)
            for channel in 0..<channelCount {
                let samples = channels[channel]
                for frame in 0..<frameLength {
                    let sample = Double(samples[frame])
                    sumSquares += sample * sample
                }
            }

            let sampleCount = max(1, frameLength * channelCount)
            let energy = sumSquares / Double(sampleCount)
            if energy > 0.000_000_1 {
                windowEnergies.append(energy)
            }
        }

        guard !windowEnergies.isEmpty else {
            return nil
        }

        let sorted = windowEnergies.sorted(by: >)
        let retainedCount = max(1, Int(ceil(Double(sorted.count) * 0.6)))
        let gatedEnergy = sorted.prefix(retainedCount).reduce(0, +) / Double(retainedCount)
        return 10 * log10(gatedEnergy)
    }

    private nonisolated static func balancedPlaybackVolume(measuredDB: Double?) -> Float {
        guard let measuredDB, measuredDB.isFinite else {
            return 1
        }

        let targetDB = -15.0
        let gain = pow(10, (targetDB - measuredDB) / 20)
        return Float(min(1, max(0.72, gain)))
    }

    private func downloadTemporaryAudio(from audioURL: URL, cookie: String) async throws -> URL {
        var request = URLRequest(url: audioURL)
        request.timeoutInterval = 30
        for (key, value) in Self.playbackHeaders(cookie: cookie) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw NativeAudioError.downloadFailed("音频下载失败 HTTP \(httpResponse.statusCode)")
            }

            let targetURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("eno-audio-\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            try FileManager.default.moveItem(at: temporaryURL, to: targetURL)
            return targetURL
        } catch let error as NativeAudioError {
            throw error
        } catch {
            throw NativeAudioError.downloadFailed("音频下载失败：\(error.localizedDescription)")
        }
    }

    nonisolated static func playbackHeaders(cookie: String) -> [String: String] {
        var headers = [
            "Referer": "https://www.bilibili.com/",
            "Origin": "https://www.bilibili.com",
            "Accept": "*/*",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ]
        if !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        return headers
    }

    private func loadArtwork(from artworkURL: String?) {
        guard let artworkURL, let url = URL(string: artworkURL) else { return }
        let requestID = playbackRequestID
        artworkTask = Task { [weak self] in
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                for (key, value) in Self.playbackHeaders(cookie: "") {
                    request.setValue(value, forHTTPHeaderField: key)
                }
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let self, !Task.isCancelled, self.isCurrentPlaybackRequest(requestID),
                      let response = response as? HTTPURLResponse,
                      (200...299).contains(response.statusCode),
                      let image = UIImage(data: data) else { return }
                self.currentArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.updateNowPlaying()
            } catch { return }
        }
    }

    private func removeTemporaryAudio() {
        if let temporaryAudioURL {
            try? FileManager.default.removeItem(at: temporaryAudioURL)
            self.temporaryAudioURL = nil
        }
    }

    @discardableResult
    nonisolated static func removeStaleTemporaryAudio() -> (deletedFiles: Int, deletedBytes: Int64) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: manager.temporaryDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else {
            return (0, 0)
        }

        var deletedFiles = 0
        var deletedBytes: Int64 = 0
        for file in files where shouldRemoveTemporaryFile(file) {
            let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            do {
                try manager.removeItem(at: file)
                deletedFiles += 1
                deletedBytes += size
            } catch {
                continue
            }
        }
        return (deletedFiles, deletedBytes)
    }

    private nonisolated static func shouldRemoveTemporaryFile(_ file: URL) -> Bool {
        let name = file.lastPathComponent
        if name.hasPrefix(managedTemporaryAudioPrefix) {
            return true
        }

        guard name.hasPrefix(systemDownloadTemporaryPrefix),
              let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
              let modifiedAt = values.contentModificationDate
        else {
            return false
        }

        return Date().timeIntervalSince(modifiedAt) > staleSystemDownloadAge
    }

    private func startProgressTimer() {
        stopProgressTimer()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sendProgress() }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func sendState(_ state: String, message: String = "") {
        sendEvent("native-audio-state", [
            "state": state, "title": currentTitle, "artist": currentArtist,
            "message": message, "position": core.position, "duration": core.duration
        ])
    }

    private func sendProgress() {
        sendEvent("native-audio-progress", [
            "position": core.position, "duration": core.duration, "isPlaying": core.isPlaying
        ])
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTitle,
            MPMediaItemPropertyArtist: currentArtist,
            MPNowPlayingInfoPropertyPlaybackRate: core.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: core.position,
            MPMediaItemPropertyPlaybackDuration: core.duration
        ]
        if let currentArtwork { info[MPMediaItemPropertyArtwork] = currentArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureSessionObservers() {
        let center = NotificationCenter.default
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                self?.handleInterruption(type: type, options: options)
            }
        })
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let previous = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let previousPorts = previous?.outputs.map { $0.portType.rawValue }.joined(separator: ",") ?? "unknown"
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logAudioRoute("route changed reason=\(reason ?? 0) previous=[\(previousPorts)]")
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                    || reason == AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue {
                    self.needsSessionReset = true
                    self.needsEngineRecreation = true
                    self.needsGraphRecovery = true
                    _ = self.pause()
                } else {
                    self.scheduleEngineRecovery(recreateEngine: reason != AVAudioSession.RouteChangeReason.categoryChange.rawValue)
                }
            }
        })
        sessionObservers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] notification in
            let engine = notification.object as? AVAudioEngine
            Task { @MainActor [weak self] in
                guard let self, engine === self.core.audioEngine, !self.isRebuilding else { return }
                self.scheduleEngineRecovery(recreateEngine: true)
            }
        })
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleEngineRecovery(recreateEngine: true)
            }
        })
    }

    private func handleInterruption(type: UInt?, options: UInt) {
        guard let type, let interruption = AVAudioSession.InterruptionType(rawValue: type) else { return }
        switch interruption {
        case .began:
            interruptionGeneration += 1
            isInterrupted = true
            needsGraphRecovery = true
            resumeAfterInterruption = wantsPlayback
            recoveryTask?.cancel()
            core.pause()
            stopProgressTimer()
            sendProgress()
            updateNowPlaying()
            sendState("paused")
        case .ended:
            guard isInterrupted else { return }
            isInterrupted = false
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                && resumeAfterInterruption && wantsPlayback
            resumeAfterInterruption = false
            if shouldResume {
                scheduleEngineRecovery(recreateEngine: false)
            } else {
                wantsPlayback = false
                sendState("paused")
            }
        @unknown default:
            break
        }
    }

    private func scheduleEngineRecovery(recreateEngine: Bool) {
        needsEngineRecreation = needsEngineRecreation || recreateEngine
        needsGraphRecovery = true
        guard !isInterrupted else { return }
        guard core.hasAudio || needsEngineRecreation else { return }
        guard wantsPlayback else { return }
        recoveryTask?.cancel()
        let requestID = playbackRequestID
        core.pause()
        stopProgressTimer()
        updateNowPlaying()
        if wantsPlayback && core.hasAudio {
            sendState("buffering", message: "正在恢复音频输出...")
        }
        recoveryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 150_000_000) }
            catch { return }
            guard let self, self.isCurrentPlaybackRequest(requestID), !self.isInterrupted, self.wantsPlayback else { return }
            self.isRebuilding = true
            defer { self.isRebuilding = false }
            do {
                try self.activateSession()
                try self.core.rebuild(recreateEngine: self.needsEngineRecreation, resume: self.wantsPlayback)
                self.needsEngineRecreation = false
                self.needsGraphRecovery = false
                if self.core.isPlaying { self.startProgressTimer() }
                self.sendProgress()
                self.updateNowPlaying()
                self.sendState(self.core.isPlaying ? "playing" : "paused")
            } catch {
                self.sendState("failed", message: error.localizedDescription)
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        addRemoteTarget(center.playCommand) { [weak self] _ in
            guard let self else { return .commandFailed }
            _ = self.resume()
            return .success
        }
        addRemoteTarget(center.pauseCommand) { [weak self] _ in
            guard let self else { return .commandFailed }
            _ = self.pause()
            return .success
        }
        addRemoteTarget(center.togglePlayPauseCommand) { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.wantsPlayback { _ = self.pause() } else { _ = self.resume() }
            return .success
        }
        center.changePlaybackPositionCommand.isEnabled = true
        addRemoteTarget(center.changePlaybackPositionCommand) { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            _ = self.seek(seconds: event.positionTime)
            return .success
        }
        center.nextTrackCommand.isEnabled = true
        addRemoteTarget(center.nextTrackCommand) { [weak self] _ in
            self?.sendEvent("native-audio-command", ["command": "next"])
            return .success
        }
        center.previousTrackCommand.isEnabled = true
        addRemoteTarget(center.previousTrackCommand) { [weak self] _ in
            self?.sendEvent("native-audio-command", ["command": "previous"])
            return .success
        }
    }

    private func addRemoteTarget(_ command: MPRemoteCommand, handler: @escaping @MainActor (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        let token = command.addTarget { event in
            if Thread.isMainThread {
                return MainActor.assumeIsolated { handler(event) }
            }
            DispatchQueue.main.async { _ = handler(event) }
            return .success
        }
        remoteTargets.append((command, token))
    }

    deinit {
        artworkTask?.cancel()
        volumeTask?.cancel()
        recoveryTask?.cancel()
        progressTimer?.invalidate()
        for observer in sessionObservers { NotificationCenter.default.removeObserver(observer) }
        for (command, token) in remoteTargets { command.removeTarget(token) }
        if let temporaryAudioURL { try? FileManager.default.removeItem(at: temporaryAudioURL) }
    }
}

struct BMusicAudioCacheEntry: Codable {
    var id: String
    var fileName: String
    var lastAccessed: Date
}

actor BMusicAudioCache {
    static let shared = BMusicAudioCache()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let indexURL: URL
    private var entries: [String: BMusicAudioCacheEntry] = [:]
    private var activePlaybackDownloadTask: URLSessionDownloadTask?
    private var activePlaybackDownloadToken: UUID?
    private var pendingDownloads: [String: Task<URL, Error>] = [:]

    private init() {
        let manager = FileManager.default
        let baseDirectory = manager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let directory = baseDirectory.appendingPathComponent("BMusicAudio", isDirectory: true)
        cacheDirectory = directory
        indexURL = directory.appendingPathComponent("index.json")
        entries = Self.loadEntries(from: directory.appendingPathComponent("index.json"))
    }

    func audioURL(
        for id: String,
        sourceURL: URL,
        cookie: String,
        cancelingActivePlaybackDownload: Bool = false
    ) async throws -> URL {
        if let cachedURL = cachedURL(for: id) {
            return cachedURL
        }

        // Playback and background caching share one download for each song.
        if let pending = pendingDownloads[id] {
            return try await pending.value
        }

        if cancelingActivePlaybackDownload {
            cancelActivePlaybackDownload()
        }

        let pending = Task {
            let temporaryURL = try await self.downloadAudio(
                from: sourceURL,
                cookie: cookie,
                tracksPlaybackDownload: cancelingActivePlaybackDownload
            )
            do {
                return try self.storeDownloadedAudio(at: temporaryURL, for: id)
            } catch {
                try? self.fileManager.removeItem(at: temporaryURL)
                throw error
            }
        }
        pendingDownloads[id] = pending
        defer { pendingDownloads[id] = nil }
        return try await pending.value
    }

    func cachedURL(for id: String, legacyID: String? = nil) -> URL? {
        if entries[id] == nil, let legacyID, let legacyURL = cachedURL(for: legacyID),
           let legacy = entries[legacyID] {
            entries[id] = BMusicAudioCacheEntry(id: id, fileName: legacy.fileName, lastAccessed: Date())
            saveEntries()
            return legacyURL
        }
        guard var entry = entries[id] else {
            return nil
        }

        let url = cacheDirectory.appendingPathComponent(entry.fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            entries[id] = nil
            saveEntries()
            return nil
        }

        entry.lastAccessed = Date()
        entries[id] = entry
        saveEntries()
        return url
    }

    func prune(keeping keepIDs: Set<String>) {
        let retainedFiles = Set(entries.filter { keepIDs.contains($0.key) }.map { $0.value.fileName })
        for (id, entry) in entries where !keepIDs.contains(id) {
            let url = cacheDirectory.appendingPathComponent(entry.fileName)
            if !retainedFiles.contains(entry.fileName) {
                try? fileManager.removeItem(at: url)
            }
            entries[id] = nil
        }
        saveEntries()
    }

    func clear(keeping keepIDs: Set<String> = []) {
        prune(keeping: keepIDs)
    }

    func sizeInBytes() -> Int64 {
        Set(entries.values.map(\.fileName)).reduce(into: Int64(0)) { total, fileName in
            let url = cacheDirectory.appendingPathComponent(fileName)
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else {
                return
            }
            total += Int64(values.fileSize ?? 0)
        }
    }

    func cachedIDs() -> Set<String> {
        Set(entries.keys)
    }

    private func cancelActivePlaybackDownload() {
        activePlaybackDownloadTask?.cancel()
        activePlaybackDownloadTask = nil
        activePlaybackDownloadToken = nil
    }

    private func downloadAudio(from audioURL: URL, cookie: String, tracksPlaybackDownload: Bool = false) async throws -> URL {
        var request = URLRequest(url: audioURL)
        request.timeoutInterval = 30
        for (key, value) in NativeAudioPlayer.playbackHeaders(cookie: cookie) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (temporaryURL, response, token) = try await downloadFile(
                request: request,
                tracksPlaybackDownload: tracksPlaybackDownload
            )
            if tracksPlaybackDownload,
               activePlaybackDownloadToken == token {
                activePlaybackDownloadTask = nil
                activePlaybackDownloadToken = nil
            }
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                try? fileManager.removeItem(at: temporaryURL)
                throw NativeAudioError.downloadFailed("音频下载失败 HTTP \(httpResponse.statusCode)")
            }
            return temporaryURL
        } catch let error as NativeAudioError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw NativeAudioError.downloadFailed("音频下载失败：\(error.localizedDescription)")
        }
    }

    private func downloadFile(
        request: URLRequest,
        tracksPlaybackDownload: Bool
    ) async throws -> (URL, URLResponse, UUID) {
        try await withCheckedThrowingContinuation { continuation in
            let token = UUID()
            let task = URLSession.shared.downloadTask(with: request) { temporaryURL, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let temporaryURL, let response else {
                    continuation.resume(throwing: NativeAudioError.downloadFailed("音频下载失败：没有收到文件"))
                    return
                }

                // URLSession owns the original file only until this callback returns.
                let retainedURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("eno-audio-\(UUID().uuidString).m4a")
                do {
                    try FileManager.default.moveItem(at: temporaryURL, to: retainedURL)
                    continuation.resume(returning: (retainedURL, response, token))
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            if tracksPlaybackDownload {
                activePlaybackDownloadTask = task
                activePlaybackDownloadToken = token
            }

            task.resume()
        }
    }

    private func storeDownloadedAudio(at temporaryURL: URL, for id: String) throws -> URL {
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        if let oldEntry = entries[id] {
            try? fileManager.removeItem(at: cacheDirectory.appendingPathComponent(oldEntry.fileName))
        }

        let fileName = "\(safeFileName(for: id)).m4a"
        let targetURL = cacheDirectory.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: targetURL)
        try fileManager.moveItem(at: temporaryURL, to: targetURL)

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = targetURL
        try? mutableURL.setResourceValues(resourceValues)

        entries[id] = BMusicAudioCacheEntry(id: id, fileName: fileName, lastAccessed: Date())
        saveEntries()
        return targetURL
    }

    private func safeFileName(for id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return id.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }.joined()
    }

    private static func loadEntries(from url: URL) -> [String: BMusicAudioCacheEntry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: BMusicAudioCacheEntry].self, from: data)
        else {
            return [:]
        }
        return entries
    }

    private func saveEntries() {
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            return
        }
    }
}
