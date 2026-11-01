import AVFoundation
import AVKit
import Combine
import MediaPlayer
import SwiftUI

@MainActor
final class PlayerViewModel: ObservableObject {
    let player = AVPlayer()

    @Published var videoDetail: VideoDetail?
    @Published var selectedSource: VideoStreamSource?
    @Published var selectedSubtitleTrack: SubtitleTrack?
    @Published var activeSubtitleText: String?
    @Published var subtitleOffset: TimeInterval = 0.0
    @Published var subtitleFontSize: CGFloat = 18.0

    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = true
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var playbackSpeed: Float = 1.0
    @Published var isAspectFill: Bool = false
    @Published var isPiPActive: Bool = false
    @Published var errorMessage: String?

    private var subtitleCues: [SubtitleCue] = []
    private var timeObserverToken: Any?
    private var statusCancellable: AnyCancellable?
    private var timeControlCancellable: AnyCancellable?
    private var lastSavedProgressTime: Double = 0

    init() {
        configureAudioSession()
        setupRemoteTransportControls()
        observePlayerState()
    }

    // MARK: - Load Video (Online or Offline)

    func loadVideo(detail: VideoDetail, resumeFrom: Double? = nil) {
        self.videoDetail = detail

        // Check if downloaded offline first
        if let downloaded = DownloadManager.shared.completedDownload(for: detail.item),
           let localURL = downloaded.localFileURL {
            let localSource = VideoStreamSource(
                label: "Offline (\(downloaded.qualityLabel))",
                resolution: 1080,
                url: localURL,
                isPremiumOriginal: true,
                fileExtension: localURL.pathExtension
            )
            self.selectedSource = localSource
            replacePlayerItem(with: localURL, videoPageURL: detail.item.pageURL, seekTo: resumeFrom)
        } else if let initialSource = detail.bestSource {
            self.selectedSource = initialSource
            replacePlayerItem(with: initialSource.url, videoPageURL: detail.item.pageURL, seekTo: resumeFrom)
        }

        // Auto-select Czech or Slovak subtitle track if available
        if let preferredSub = detail.subtitles.first(where: {
            $0.language.contains("svk") || $0.language.contains("sk") || $0.language.contains("cze") || $0.language.contains("cs")
        }) ?? detail.subtitles.first(where: { $0.isDefault }) {
            selectSubtitle(preferredSub)
        }

        updateNowPlayingMetadata()
    }

    // MARK: - Switch Stream Quality Seamlessly

    func selectSource(_ source: VideoStreamSource) {
        guard selectedSource?.id != source.id else { return }
        let savedTime = currentTime
        selectedSource = source
        replacePlayerItem(
            with: source.url,
            videoPageURL: videoDetail?.item.pageURL,
            seekTo: savedTime > 2 ? savedTime : nil
        )
    }

    // MARK: - Switch Subtitle Track

    func selectSubtitle(_ track: SubtitleTrack?) {
        selectedSubtitleTrack = track
        activeSubtitleText = nil
        subtitleCues = []

        guard let track else { return }

        // Check if offline subtitle exists first
        if let item = videoDetail?.item,
           let downloaded = DownloadManager.shared.completedDownload(for: item),
           let relPath = downloaded.localSubtitlePaths[track.language],
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let localVTT = docs.appendingPathComponent(relPath)
            if let content = try? String(contentsOf: localVTT, encoding: .utf8) {
                subtitleCues = VTTParser.parse(content: content)
                return
            }
        }

        Task {
            do {
                let cues = try await PrehrajToClient.shared.fetchSubtitleCues(from: track)
                self.subtitleCues = cues
            } catch {
                print("Subtitle load failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.playImmediately(atRate: playbackSpeed)
        }
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        let targetTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        updateSubtitleForCurrentTime(clamped)
        updateNowPlayingMetadata()
    }

    func skip(by deltaSeconds: Double) {
        seek(to: currentTime + deltaSeconds)
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player.rate = speed
        }
    }

    func cleanup() {
        saveCurrentProgress(force: true)
        player.pause()
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - Internal AVPlayer Setup

    private func replacePlayerItem(with url: URL, videoPageURL: URL?, seekTo: Double?) {
        isBuffering = true
        errorMessage = nil

        let asset: AVURLAsset
        if url.isFileURL {
            asset = AVURLAsset(url: url)
        } else {
            var headers: [String: String] = [
                "User-Agent": PrehrajToClient.userAgent
            ]
            if let referer = videoPageURL?.absoluteString {
                headers["Referer"] = referer
            }
            asset = AVURLAsset(
                url: url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
            )
        }

        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 15

        statusCancellable = playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.isBuffering = false
                    let itemSeconds = playerItem.duration.seconds
                    if itemSeconds.isFinite && itemSeconds > 0 {
                        self.duration = itemSeconds
                    }
                    if let seekTo, seekTo > 1 {
                        self.seek(to: seekTo)
                    }
                    self.player.playImmediately(atRate: self.playbackSpeed)
                    self.updateNowPlayingMetadata()
                case .failed:
                    self.isBuffering = false
                    self.errorMessage = playerItem.error?.localizedDescription ?? "Chyba prehrávania streamu."
                default:
                    break
                }
            }

        player.replaceCurrentItem(with: playerItem)
    }

    private func observePlayerState() {
        timeControlCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .playing:
                    self.isPlaying = true
                    self.isBuffering = false
                case .paused:
                    self.isPlaying = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isBuffering = true
                @unknown default:
                    break
                }
            }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            guard seconds.isFinite && seconds >= 0 else { return }

            Task { @MainActor in
                self.currentTime = seconds
                if let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite && itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.updateSubtitleForCurrentTime(seconds)
                self.saveCurrentProgress(force: false)
            }
        }
    }

    private func updateSubtitleForCurrentTime(_ seconds: Double) {
        guard !subtitleCues.isEmpty else {
            if activeSubtitleText != nil { activeSubtitleText = nil }
            return
        }
        let cue = VTTParser.activeCue(at: seconds, in: subtitleCues, offset: subtitleOffset)
        if activeSubtitleText != cue?.text {
            activeSubtitleText = cue?.text
        }
    }

    private func saveCurrentProgress(force: Bool) {
        guard let video = videoDetail?.item, duration > 10 else { return }
        if force || abs(currentTime - lastSavedProgressTime) >= 5.0 {
            lastSavedProgressTime = currentTime
            LibraryManager.shared.updateProgress(
                for: video,
                currentTime: currentTime,
                duration: duration,
                qualityLabel: selectedSource?.label
            )
        }
    }

    // MARK: - Audio Session & Lock Screen Controls

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            print("AVAudioSession error: \(error.localizedDescription)")
        }
    }

    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.player.playImmediately(atRate: self.playbackSpeed)
            }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.player.pause()
            }
            return .success
        }
        commandCenter.skipForwardCommand.preferredIntervals = [10]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.skip(by: 10)
            }
            return .success
        }
        commandCenter.skipBackwardCommand.preferredIntervals = [10]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.skip(by: -10)
            }
            return .success
        }
    }

    private func updateNowPlayingMetadata() {
        guard let video = videoDetail?.item else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: video.title,
            MPMediaItemPropertyArtist: "Prehraj.to • \(selectedSource?.label ?? "HD")",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackSpeed : 0.0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
