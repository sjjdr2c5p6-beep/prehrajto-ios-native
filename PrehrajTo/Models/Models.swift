import Foundation
import SwiftUI

// MARK: - Video Search & Detail Models

struct VideoItem: Identifiable, Codable, Hashable {
    var id: String { "\(videoSlug)-\(videoId)" }
    let videoId: String
    let videoSlug: String
    let title: String
    let duration: String
    let fileSize: String
    let thumbnailURL: URL?
    let previewImages: [URL]
    let isHD: Bool
    let pageURL: URL

    var formattedPath: String {
        "/\(videoSlug)/\(videoId)"
    }
}

struct VideoStreamSource: Identifiable, Codable, Hashable {
    var id: String { "\(label)-\(url.absoluteString)" }
    let label: String          // e.g., "Originál (Premium)", "1080p", "720p", "480p"
    let resolution: Int        // e.g., 2160, 1080, 720, 480, 360
    let url: URL
    let isPremiumOriginal: Bool
    let fileExtension: String  // e.g., "mp4", "mkv", "m3u8"

    var badgeText: String {
        if isPremiumOriginal { return "ORIGINÁL • PREMIUM" }
        if resolution >= 1080 { return "FULL HD • \(label)" }
        if resolution >= 720 { return "HD • \(label)" }
        return label
    }
}

struct SubtitleTrack: Identifiable, Codable, Hashable {
    var id: String { "\(language)-\(url.absoluteString)" }
    let label: String          // e.g., "CZE - Čeština", "SVK - Slovenčina"
    let language: String       // e.g., "cze", "svk", "eng"
    let url: URL
    let isDefault: Bool
}

struct SubtitleCue: Identifiable, Equatable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

struct VideoDetail: Identifiable {
    var id: String { item.id }
    let item: VideoItem
    let sources: [VideoStreamSource]
    let subtitles: [SubtitleTrack]
    let descriptionText: String?
    let viewsCount: String?
    let uploadedDate: String?

    var bestSource: VideoStreamSource? {
        sources.sorted { lhs, rhs in
            if lhs.isPremiumOriginal != rhs.isPremiumOriginal {
                return lhs.isPremiumOriginal
            }
            return lhs.resolution > rhs.resolution
        }.first
    }
}

// MARK: - Watch History & Progress

struct WatchProgressItem: Identifiable, Codable, Hashable {
    var id: String { video.id }
    let video: VideoItem
    var currentTime: Double
    var duration: Double
    var lastWatchedAt: Date
    var selectedQualityLabel: String?

    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0.0), 1.0)
    }

    var remainingTimeFormatted: String {
        let remaining = max(Int(duration - currentTime), 0)
        let minutes = remaining / 60
        if minutes >= 60 {
            let hrs = minutes / 60
            let mins = minutes % 60
            return "Zostáva \(hrs)h \(mins)m"
        }
        return "Zostáva \(minutes) min"
    }
}

// MARK: - Offline Downloads

enum DownloadState: String, Codable {
    case queued
    case downloading
    case paused
    case completed
    case failed
}

struct DownloadedVideo: Identifiable, Codable, Hashable {
    var id: String { video.id }
    let video: VideoItem
    let qualityLabel: String
    var state: DownloadState
    var progress: Double
    var totalBytes: Int64
    var downloadedBytes: Int64
    var localRelativePath: String?
    var localSubtitlePaths: [String: String] // languageCode : relativePath
    var createdAt: Date
    var errorMessage: String?

    var localFileURL: URL? {
        guard let localRelativePath else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent(localRelativePath)
    }
}

// MARK: - Premium Account

struct PremiumAccountInfo: Codable, Equatable {
    let email: String
    var isPremium: Bool
    var premiumUntil: String?
    var creditRemaining: String?
    var authMethod: AuthMethod
    var lastVerified: Date

    enum AuthMethod: String, Codable {
        case credentials = "Prihlasovacie údaje"
        case tokenCookie = "Session / Refresh Token"
    }
}

// MARK: - Search Filters & Categories

enum SearchFilter: String, CaseIterable, Identifiable {
    case all = "Všetko"
    case hdOnly = "HD / 1080p+"
    case largeFiles = "Vysoká kvalita (>1.5 GB)"
    case czSk = "CZ / SK Dabing"

    var id: String { rawValue }
}

struct DiscoveryCategory: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let query: String
    let icon: String
    let gradientColors: [Color]
}
