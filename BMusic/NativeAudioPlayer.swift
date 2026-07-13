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

final class NativeAudioPlayer {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var periodicTimeObserver: Any?
    private var currentTitle = ""
    private var currentArtist = ""
    private var currentArtwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var temporaryAudioURL: URL?
    private var equalizedTemporaryAudioURL: URL?
    private var playbackRequestID = UUID()
    private var volumeBalancingEnabled = true
    private var equalizerPreset: BMusicEqualizerPreset = .off
    private var balancedVolumes: [String: Float] = [:]
    private static let managedTemporaryAudioPrefix = "eno-audio-"
    private static let systemDownloadTemporaryPrefix = "CFNetworkDownload"
    private static let staleSystemDownloadAge: TimeInterval = 300
    private let sendEvent: (String, [String: Any]) -> Void

    init(sendEvent: @escaping (String, [String: Any]) -> Void = { _, _ in }) {
        self.sendEvent = sendEvent
        Self.removeStaleTemporaryAudio()
        configureRemoteCommands()
    }

    func setVolumeBalancingEnabled(_ enabled: Bool) {
        volumeBalancingEnabled = enabled
        player?.volume = enabled ? (player?.volume ?? 1) : 1
    }

    func setEqualizerPreset(_ preset: BMusicEqualizerPreset) {
        equalizerPreset = preset
    }

    func playCached(cacheID: String, title: String?, artist: String?, artworkURL: String?) async throws -> Bool {
        guard let localURL = await BMusicAudioCache.shared.cachedURL(for: cacheID) else {
            return false
        }

        let requestID = UUID()
        playbackRequestID = requestID
        artworkTask?.cancel()
        artworkTask = nil
        currentArtwork = nil
        cleanupObservers()
        player?.pause()
        player = nil
        playerItem = nil
        removeTemporaryAudio()
        currentTitle = title ?? ""
        currentArtist = artist ?? ""
        loadArtwork(from: artworkURL)
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try AVAudioSession.sharedInstance().setActive(true)

        sendState("loading", message: "正在读取缓存...")
        guard isCurrentPlaybackRequest(requestID) else {
            throw CancellationError()
        }

        let playbackURL = await equalizedPlaybackURL(for: localURL, preset: equalizerPreset, requestID: requestID) ?? localURL
        guard isCurrentPlaybackRequest(requestID) else {
            throw CancellationError()
        }
        let item = AVPlayerItem(url: playbackURL)
        let player = AVPlayer(playerItem: item)
        let volume = await playbackVolume(for: localURL, requestID: requestID)
        guard isCurrentPlaybackRequest(requestID) else {
            throw CancellationError()
        }
        player.volume = volume
        self.playerItem = item
        self.player = player
        observe(item: item, player: player)
        updateNowPlaying(playbackRate: 1)
        sendState("loading")
        player.play()

        return true
    }

    func play(url: String, title: String?, artist: String?, artworkURL: String?, cookie: String = "", cacheID: String? = nil) async throws -> Any {
        guard let audioURL = URL(string: url) else {
            throw NativeAudioError.invalidURL
        }

        let requestID = UUID()
        playbackRequestID = requestID
        artworkTask?.cancel()
        artworkTask = nil
        currentArtwork = nil
        cleanupObservers()
        player?.pause()
        player = nil
        playerItem = nil
        removeTemporaryAudio()
        currentTitle = title ?? ""
        currentArtist = artist ?? ""
        loadArtwork(from: artworkURL)
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try AVAudioSession.sharedInstance().setActive(true)

        sendState("loading", message: "正在准备音频...")
        let localURL: URL
        do {
            if let cacheID {
                localURL = try await BMusicAudioCache.shared.audioURL(
                    for: cacheID,
                    sourceURL: audioURL,
                    cookie: cookie,
                    cancelingActivePlaybackDownload: true
                )
            } else {
                localURL = try await downloadTemporaryAudio(from: audioURL, cookie: cookie)
                temporaryAudioURL = localURL
            }
        } catch {
            if !isCurrentPlaybackRequest(requestID) {
                throw CancellationError()
            }
            throw error
        }
        guard isCurrentPlaybackRequest(requestID) else {
            if cacheID == nil {
                try? FileManager.default.removeItem(at: localURL)
            }
            throw CancellationError()
        }

        let playbackURL = await equalizedPlaybackURL(for: localURL, preset: equalizerPreset, requestID: requestID) ?? localURL
        guard isCurrentPlaybackRequest(requestID) else {
            throw CancellationError()
        }
        let item = AVPlayerItem(url: playbackURL)
        let player = AVPlayer(playerItem: item)
        let volume = await playbackVolume(for: localURL, requestID: requestID)
        guard isCurrentPlaybackRequest(requestID) else {
            throw CancellationError()
        }
        player.volume = volume
        self.playerItem = item
        self.player = player
        observe(item: item, player: player)
        updateNowPlaying(playbackRate: 1)
        sendState("loading")
        player.play()

        return [
            "success": true,
            "title": title ?? "",
            "artist": artist ?? ""
        ]
    }

    func pause() -> Any {
        player?.pause()
        updateNowPlaying(playbackRate: 0)
        sendState("paused")
        return ["success": true]
    }

    func resume() -> Any {
        player?.play()
        updateNowPlaying(playbackRate: 1)
        sendState("playing")
        return ["success": true]
    }

    func stop() -> Any {
        playbackRequestID = UUID()
        player?.pause()
        cleanupObservers()
        player = nil
        playerItem = nil
        artworkTask?.cancel()
        artworkTask = nil
        currentArtwork = nil
        removeTemporaryAudio()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        sendState("stopped")
        return ["success": true]
    }

    func seek(seconds: Double) -> Any {
        guard let player else {
            return ["success": false]
        }

        let safeSeconds = max(0, seconds)
        let time = CMTime(seconds: safeSeconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                self?.sendProgress()
                self?.updateNowPlaying(playbackRate: player.rate)
            }
        }

        return ["success": true, "position": safeSeconds]
    }

    private func isCurrentPlaybackRequest(_ requestID: UUID) -> Bool {
        playbackRequestID == requestID
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

    private static func estimateLoudnessDB(for url: URL) -> Double? {
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

    private static func balancedPlaybackVolume(measuredDB: Double?) -> Float {
        guard let measuredDB, measuredDB.isFinite else {
            return 1
        }

        let targetDB = -15.0
        let gain = pow(10, (targetDB - measuredDB) / 20)
        return Float(min(1, max(0.72, gain)))
    }

    private func equalizedPlaybackURL(for url: URL, preset: BMusicEqualizerPreset, requestID: UUID) async -> URL? {
        guard preset != .off, preset != .flat else {
            return nil
        }

        sendState("loading", message: "正在应用均衡器...")
        let outputURL = await Task.detached(priority: .userInitiated) {
            Self.renderEqualizedAudio(from: url, preset: preset)
        }.value

        guard isCurrentPlaybackRequest(requestID) else {
            if let outputURL {
                try? FileManager.default.removeItem(at: outputURL)
            }
            return nil
        }

        equalizedTemporaryAudioURL = outputURL
        return outputURL
    }

    private static func renderEqualizedAudio(from inputURL: URL, preset: BMusicEqualizerPreset) -> URL? {
        do {
            let inputFile = try AVAudioFile(forReading: inputURL)
            let processingFormat = inputFile.processingFormat
            guard inputFile.length > 0 else {
                return nil
            }

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let eq = AVAudioUnitEQ(numberOfBands: preset.bandGains.count)
            let frequencies: [Float] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

            for (index, gain) in preset.bandGains.enumerated() {
                let band = eq.bands[index]
                band.filterType = .parametric
                band.frequency = frequencies[index]
                band.bandwidth = 0.5
                band.gain = gain
                band.bypass = false
            }

            engine.attach(player)
            engine.attach(eq)
            engine.connect(player, to: eq, format: processingFormat)
            engine.connect(eq, to: engine.mainMixerNode, format: processingFormat)

            let maximumFrameCount: AVAudioFrameCount = 4096
            try engine.enableManualRenderingMode(.offline, format: processingFormat, maximumFrameCount: maximumFrameCount)
            try engine.start()

            player.scheduleFile(inputFile, at: nil)
            player.play()

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("eno-audio-eq-\(UUID().uuidString)")
                .appendingPathExtension("caf")
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: engine.manualRenderingFormat.settings)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat,
                frameCapacity: engine.manualRenderingMaximumFrameCount
            ) else {
                engine.stop()
                return nil
            }

            while engine.manualRenderingSampleTime < inputFile.length {
                let remainingFrames = inputFile.length - engine.manualRenderingSampleTime
                let framesToRender = AVAudioFrameCount(min(Int64(engine.manualRenderingMaximumFrameCount), remainingFrames))

                switch try engine.renderOffline(framesToRender, to: buffer) {
                case .success:
                    try outputFile.write(from: buffer)
                case .insufficientDataFromInputNode:
                    continue
                case .cannotDoInCurrentContext:
                    continue
                case .error:
                    engine.stop()
                    try? FileManager.default.removeItem(at: outputURL)
                    return nil
                @unknown default:
                    engine.stop()
                    try? FileManager.default.removeItem(at: outputURL)
                    return nil
                }
            }

            player.stop()
            engine.stop()
            return outputURL
        } catch {
            return nil
        }
    }

    private func observe(item: AVPlayerItem, player: AVPlayer) {
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self?.updateNowPlaying(playbackRate: player.rate)
                    self?.sendProgress()
                    self?.sendState("ready")
                case .failed:
                    self?.sendState("failed", message: self?.failureMessage(for: item) ?? "播放失败")
                case .unknown:
                    self?.sendState("loading")
                @unknown default:
                    self?.sendState("unknown")
                }
            }
        }

        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                switch player.timeControlStatus {
                case .paused:
                    self?.updateNowPlaying(playbackRate: 0)
                    self?.sendState("paused")
                case .waitingToPlayAtSpecifiedRate:
                    self?.sendState("buffering")
                case .playing:
                    self?.updateNowPlaying(playbackRate: 1)
                    self?.sendState("playing")
                @unknown default:
                    self?.sendState("unknown")
                }
            }
        }

        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            self?.sendProgress()
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.updateNowPlaying(playbackRate: 0)
            self?.sendState("ended")
        }
    }

    private func failureMessage(for item: AVPlayerItem) -> String {
        var messages: [String] = []
        if let error = item.error {
            messages.append(error.localizedDescription)
        }

        if let events = item.errorLog()?.events, let event = events.last {
            if let comment = event.errorComment, !comment.isEmpty {
                messages.append(comment)
            }
            if event.errorStatusCode != 0 {
                messages.append("HTTP \(event.errorStatusCode)")
            }
        }

        return messages.isEmpty ? "播放失败" : messages.joined(separator: " · ")
    }

    private func cleanupObservers() {
        statusObserver?.invalidate()
        statusObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil

        if let periodicTimeObserver, let player {
            player.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
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

    static func playbackHeaders(cookie: String) -> [String: String] {
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
        guard let artworkURL, !artworkURL.isEmpty, let url = URL(string: artworkURL) else {
            return
        }

        artworkTask = Task { [weak self] in
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                for (key, value) in Self.playbackHeaders(cookie: "") {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled,
                      let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let image = UIImage(data: data)
                else {
                    return
                }

                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                await MainActor.run { [weak self] in
                    let rate = self?.player?.rate ?? 0
                    self?.currentArtwork = artwork
                    self?.updateNowPlaying(playbackRate: rate)
                }
            } catch {
                return
            }
        }
    }

    private func removeTemporaryAudio() {
        if let equalizedTemporaryAudioURL {
            try? FileManager.default.removeItem(at: equalizedTemporaryAudioURL)
            self.equalizedTemporaryAudioURL = nil
        }

        guard let temporaryAudioURL else {
            Self.removeStaleTemporaryAudio()
            return
        }

        try? FileManager.default.removeItem(at: temporaryAudioURL)
        self.temporaryAudioURL = nil
        Self.removeStaleTemporaryAudio()
    }

    @discardableResult
    static func removeStaleTemporaryAudio() -> (deletedFiles: Int, deletedBytes: Int64) {
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

    private static func shouldRemoveTemporaryFile(_ file: URL) -> Bool {
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

    private func sendState(_ state: String, message: String = "") {
        sendEvent("native-audio-state", [
            "state": state,
            "title": currentTitle,
            "artist": currentArtist,
            "message": message,
            "position": player?.currentTime().seconds ?? 0,
            "duration": playerItem?.duration.seconds.isFinite == true ? playerItem?.duration.seconds ?? 0 : 0
        ])
    }

    private func sendProgress() {
        let position = player?.currentTime().seconds ?? 0
        let duration = playerItem?.duration.seconds ?? 0
        sendEvent("native-audio-progress", [
            "position": position.isFinite ? position : 0,
            "duration": duration.isFinite ? duration : 0,
            "isPlaying": (player?.rate ?? 0) > 0
        ])
    }

    private func updateNowPlaying(playbackRate: Float) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTitle,
            MPMediaItemPropertyArtist: currentArtist,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime().seconds ?? 0
        ]

        if let duration = playerItem?.duration.seconds, duration.isFinite {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        if let currentArtwork {
            info[MPMediaItemPropertyArtwork] = currentArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.player?.play()
            self?.updateNowPlaying(playbackRate: 1)
            self?.sendState("playing")
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            self?.updateNowPlaying(playbackRate: 0)
            self?.sendState("paused")
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, let player = self.player else {
                return .commandFailed
            }

            if player.rate == 0 {
                player.play()
                self.updateNowPlaying(playbackRate: 1)
                self.sendState("playing")
            } else {
                player.pause()
                self.updateNowPlaying(playbackRate: 0)
                self.sendState("paused")
            }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.sendEvent("native-audio-command", ["command": "next"])
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.sendEvent("native-audio-command", ["command": "previous"])
            return .success
        }
    }

    deinit {
        artworkTask?.cancel()
        cleanupObservers()
        removeTemporaryAudio()
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

        if cancelingActivePlaybackDownload {
            cancelActivePlaybackDownload()
        }

        let temporaryURL = try await downloadAudio(
            from: sourceURL,
            cookie: cookie,
            tracksPlaybackDownload: cancelingActivePlaybackDownload
        )
        do {
            return try storeDownloadedAudio(at: temporaryURL, for: id)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    func cachedURL(for id: String) -> URL? {
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
        for (id, entry) in entries where !keepIDs.contains(id) {
            let url = cacheDirectory.appendingPathComponent(entry.fileName)
            try? fileManager.removeItem(at: url)
            entries[id] = nil
        }
        saveEntries()
    }

    func clear(keeping keepIDs: Set<String> = []) {
        for (id, entry) in entries where !keepIDs.contains(id) {
            let url = cacheDirectory.appendingPathComponent(entry.fileName)
            try? fileManager.removeItem(at: url)
            entries[id] = nil
        }
        saveEntries()
    }

    func sizeInBytes() -> Int64 {
        entries.reduce(into: Int64(0)) { total, pair in
            let url = cacheDirectory.appendingPathComponent(pair.value.fileName)
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

                continuation.resume(returning: (temporaryURL, response, token))
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
