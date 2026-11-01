import SwiftUI

struct DownloadsView: View {
    @ObservedObject private var downloadsManager = DownloadManager.shared
    @ObservedObject private var library = LibraryManager.shared
    @State private var offlinePlayerDetail: VideoDetail?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundPrimary.ignoresSafeArea()

                if downloadsManager.downloads.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "arrow.down.circle.dotted")
                            .font(.system(size: 54))
                            .foregroundStyle(AppTheme.brandPrimary)
                        Text("Žiadne stiahnuté videá")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Otvorte detail ľubovoľného videa a klepnite na „Stiahnuť do iPhonu“ pre sledovanie bez internetu vrátane titulkov.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(downloadsManager.downloads) { entry in
                                downloadRow(entry)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Stiahnuté offline")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(item: $offlinePlayerDetail) { detail in
            let resume = library.savedProgress(for: detail.item)?.currentTime
            NativePlayerView(detail: detail, resumeTime: resume)
        }
    }

    private func downloadRow(_ entry: DownloadedVideo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AsyncImage(url: entry.video.thumbnailURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(16 / 9, contentMode: .fill)
                    default:
                        Rectangle().fill(AppTheme.backgroundSecondary)
                    }
                }
                .frame(width: 110, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.video.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text(entry.qualityLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.brandPrimary)
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(statusLabel(for: entry))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    switch entry.state {
                    case .downloading, .queued:
                        Button {
                            downloadsManager.pauseDownload(id: entry.id)
                        } label: {
                            Image(systemName: "pause.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                    case .paused:
                        Button {
                            downloadsManager.resumeDownload(id: entry.id)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppTheme.brandPrimary)
                        }
                    case .completed:
                        Button {
                            launchOfflinePlayer(entry)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(AppTheme.brandPrimary)
                        }
                    case .failed:
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }

                    Button(role: .destructive) {
                        downloadsManager.removeDownload(id: entry.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
            }

            if entry.state == .downloading || entry.state == .paused {
                ProgressView(value: entry.progress)
                    .tint(AppTheme.brandPrimary)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 16)
    }

    private func statusLabel(for entry: DownloadedVideo) -> String {
        switch entry.state {
        case .queued:
            return "Čaká v rade..."
        case .downloading:
            let pct = Int(entry.progress * 100)
            let dlMB = Double(entry.downloadedBytes) / (1024 * 1024)
            let totalMB = Double(entry.totalBytes) / (1024 * 1024)
            if totalMB > 0 {
                return String(format: "%d%% (%.0f / %.0f MB)", pct, dlMB, totalMB)
            }
            return "\(pct)%"
        case .paused:
            return "Pozastavené"
        case .completed:
            return "Pripravené na offline prehrávanie"
        case .failed:
            return entry.errorMessage ?? "Chyba sťahovania"
        }
    }

    private func launchOfflinePlayer(_ entry: DownloadedVideo) {
        guard let localURL = entry.localFileURL else { return }
        let offlineSource = VideoStreamSource(
            label: "Offline (\(entry.qualityLabel))",
            resolution: 1080,
            url: localURL,
            isPremiumOriginal: true,
            fileExtension: localURL.pathExtension
        )

        let offlineTracks: [SubtitleTrack] = entry.localSubtitlePaths.compactMap { lang, relPath in
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            let fileURL = docs.appendingPathComponent(relPath)
            return SubtitleTrack(
                label: lang.uppercased(),
                language: lang,
                url: fileURL,
                isDefault: true
            )
        }

        offlinePlayerDetail = VideoDetail(
            item: entry.video,
            sources: [offlineSource],
            subtitles: offlineTracks,
            descriptionText: nil,
            viewsCount: nil,
            uploadedDate: nil
        )
    }
}
