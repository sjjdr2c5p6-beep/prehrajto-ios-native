import Foundation
import SwiftUI

final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()

    @MainActor @Published private(set) var downloads: [DownloadedVideo] = []

    private let storageKey = "prehrajto_offline_downloads"
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var resumeDataMap: [String: Data] = [:]
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 60 * 60 * 6 // 6 hours for large movies
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    override init() {
        super.init()
        Task { @MainActor in
            loadDownloads()
        }
    }

    // MARK: - Start Download

    @MainActor
    func startDownload(
        video: VideoItem,
        source: VideoStreamSource,
        subtitles: [SubtitleTrack]
    ) {
        let id = video.id
        if let existingIndex = downloads.firstIndex(where: { $0.id == id }),
           downloads[existingIndex].state == .downloading {
            return
        }

        let newEntry = DownloadedVideo(
            video: video,
            qualityLabel: source.label,
            state: .downloading,
            progress: 0.0,
            totalBytes: 0,
            downloadedBytes: 0,
            localRelativePath: nil,
            localSubtitlePaths: [:],
            createdAt: Date(),
            errorMessage: nil
        )

        downloads.removeAll { $0.id == id }
        downloads.insert(newEntry, at: 0)
        saveDownloads()

        // Create download request with headers & cookies
        var request = URLRequest(url: source.url)
        request.setValue(PrehrajToClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(video.pageURL.absoluteString, forHTTPHeaderField: "Referer")
        PrehrajToClient.shared.applyCustomCookies(to: &request)

        let task = downloadSession.downloadTask(with: request)
        task.taskDescription = id
        activeTasks[id] = task
        task.resume()

        // Also download subtitle .vtt files in background for offline playback
        Task {
            await downloadSubtitlesForOffline(videoId: id, tracks: subtitles)
        }
    }

    @MainActor
    func pauseDownload(id: String) {
        guard let task = activeTasks[id] else { return }
        task.cancel { [weak self] data in
            Task { @MainActor in
                if let data {
                    self?.resumeDataMap[id] = data
                }
                if let idx = self?.downloads.firstIndex(where: { $0.id == id }) {
                    self?.downloads[idx].state = .paused
                    self?.saveDownloads()
                }
            }
        }
        activeTasks.removeValue(forKey: id)
    }

    @MainActor
    func resumeDownload(id: String) {
        guard let resumeData = resumeDataMap[id] else { return }
        let task = downloadSession.downloadTask(withResumeData: resumeData)
        task.taskDescription = id
        activeTasks[id] = task
        resumeDataMap.removeValue(forKey: id)

        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            downloads[idx].state = .downloading
            saveDownloads()
        }
        task.resume()
    }

    @MainActor
    func removeDownload(id: String) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
        resumeDataMap.removeValue(forKey: id)

        if let item = downloads.first(where: { $0.id == id }) {
            if let fileURL = item.localFileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                for relPath in item.localSubtitlePaths.values {
                    try? FileManager.default.removeItem(at: docs.appendingPathComponent(relPath))
                }
            }
        }

        downloads.removeAll { $0.id == id }
        saveDownloads()
    }

    @MainActor
    func completedDownload(for video: VideoItem) -> DownloadedVideo? {
        downloads.first { $0.id == video.id && $0.state == .completed && $0.localFileURL != nil }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = downloadTask.taskDescription else { return }
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0.0

        Task { @MainActor in
            guard let idx = self.downloads.firstIndex(where: { $0.id == id }) else { return }
            self.downloads[idx].progress = progress
            self.downloads[idx].downloadedBytes = totalBytesWritten
            self.downloads[idx].totalBytes = max(totalBytesExpectedToWrite, 0)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = downloadTask.taskDescription else { return }
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        let folder = docs.appendingPathComponent("PrehrajToDownloads", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let ext = downloadTask.OriginalRequestFileExtension ?? "mp4"
        let safeFileName = "\(id.replacingOccurrences(of: "/", with: "_")).\(ext)"
        let destinationURL = folder.appendingPathComponent(safeFileName)

        try? fileManager.removeItem(at: destinationURL)
        do {
            try fileManager.moveItem(at: location, to: destinationURL)
            let relativePath = "PrehrajToDownloads/\(safeFileName)"

            Task { @MainActor in
                self.activeTasks.removeValue(forKey: id)
                if let idx = self.downloads.firstIndex(where: { $0.id == id }) {
                    self.downloads[idx].state = .completed
                    self.downloads[idx].progress = 1.0
                    self.downloads[idx].localRelativePath = relativePath
                    self.saveDownloads()
                }
            }
        } catch {
            Task { @MainActor in
                if let idx = self.downloads.firstIndex(where: { $0.id == id }) {
                    self.downloads[idx].state = .failed
                    self.downloads[idx].errorMessage = error.localizedDescription
                    self.saveDownloads()
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }

        Task { @MainActor in
            self.activeTasks.removeValue(forKey: id)
            if let idx = self.downloads.firstIndex(where: { $0.id == id }) {
                self.downloads[idx].state = .failed
                self.downloads[idx].errorMessage = error.localizedDescription
                self.saveDownloads()
            }
        }
    }

    // MARK: - Offline Subtitles Helper

    private func downloadSubtitlesForOffline(videoId: String, tracks: [SubtitleTrack]) async {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = docs.appendingPathComponent("PrehrajToDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var savedMap: [String: String] = [:]
        for track in tracks {
            if let (data, _) = try? await URLSession.shared.data(from: track.url) {
                let fileName = "\(videoId)_\(track.language).vtt"
                let dest = folder.appendingPathComponent(fileName)
                try? data.write(to: dest)
                savedMap[track.language] = "PrehrajToDownloads/\(fileName)"
            }
        }

        if !savedMap.isEmpty {
            await MainActor.run {
                if let idx = self.downloads.firstIndex(where: { $0.id == videoId }) {
                    self.downloads[idx].localSubtitlePaths = savedMap
                    self.saveDownloads()
                }
            }
        }
    }

    // MARK: - Persistence

    @MainActor
    private func saveDownloads() {
        if let data = try? JSONEncoder().encode(downloads) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    @MainActor
    private func loadDownloads() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([DownloadedVideo].self, from: data) else {
            return
        }
        // Any download that was mid-flight when app terminated becomes paused/failed
        downloads = decoded.map { item in
            var copy = item
            if copy.state == .downloading {
                copy.state = .paused
            }
            return copy
        }
    }
}

private extension URLSessionTask {
    var OriginalRequestFileExtension: String? {
        guard let ext = originalRequest?.url?.pathExtension.lowercased(), !ext.isEmpty else {
            return "mp4"
        }
        if ["mp4", "mkv", "mov", "m4v", "avi"].contains(ext) {
            return ext
        }
        return "mp4"
    }
}
