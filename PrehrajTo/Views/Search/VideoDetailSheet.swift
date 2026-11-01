import SwiftUI

struct VideoDetailSheet: View {
    let item: VideoItem

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var library = LibraryManager.shared
    @ObservedObject private var downloads = DownloadManager.shared

    @State private var detail: VideoDetail?
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var selectedSource: VideoStreamSource?
    @State private var activePlayerDetail: VideoDetail?
    @State private var resumeTimestamp: Double?

    var savedProgress: WatchProgressItem? {
        library.savedProgress(for: item)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Thumbnail Hero
                        ZStack(alignment: .bottomLeading) {
                            AsyncImage(url: item.thumbnailURL) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().aspectRatio(16 / 9, contentMode: .fill)
                                default:
                                    Rectangle().fill(AppTheme.backgroundSecondary)
                                        .aspectRatio(16 / 9, contentMode: .fill)
                                }
                            }
                            .frame(height: 210)
                            .clipped()

                            AppTheme.heroOverlayGradient

                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    if item.isHD {
                                        Text("FULL HD / HD")
                                            .font(.caption2.weight(.heavy))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(AppTheme.brandGradient, in: Capsule())
                                    }
                                    if auth.isPremiumActive {
                                        Label("PREMIUM AKTÍVNE", systemImage: "crown.fill")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.black)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(AppTheme.premiumGradient, in: Capsule())
                                    }
                                }

                                Text(item.title)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(16)
                        }

                        VStack(alignment: .leading, spacing: 18) {
                            // Metadata pills
                            HStack(spacing: 12) {
                                Label(item.duration, systemImage: "clock.fill")
                                if !item.fileSize.isEmpty {
                                    Label(item.fileSize, systemImage: "internaldrive.fill")
                                }
                                if let detail, !detail.subtitles.isEmpty {
                                    Label("\(detail.subtitles.count) titulky", systemImage: "captions.bubble.fill")
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))

                            if isLoading {
                                HStack(spacing: 12) {
                                    ProgressView().tint(AppTheme.brandPrimary)
                                    Text("Načítavam priame streamy a titulky...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 28)
                                .glassCard()
                            } else if let error = errorMessage {
                                VStack(spacing: 12) {
                                    Image(systemName: "wifi.exclamationmark")
                                        .font(.title)
                                        .foregroundStyle(AppTheme.brandPrimary)
                                    Text(error)
                                        .font(.subheadline)
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                    Button("Skúsiť znova") {
                                        Task { await loadStreams() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(AppTheme.brandPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(20)
                                .glassCard()
                            } else if let detail {
                                // Primary Play & Resume Buttons
                                VStack(spacing: 10) {
                                    if let progress = savedProgress, progress.currentTime > 15 {
                                        Button {
                                            resumeTimestamp = progress.currentTime
                                            activePlayerDetail = detailWithPreferredSource(detail)
                                        } label: {
                                            HStack {
                                                Image(systemName: "play.fill")
                                                Text("Pokračovať v prehrávaní (\(formatSeconds(progress.currentTime)))")
                                                    .fontWeight(.bold)
                                            }
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 15)
                                            .background(AppTheme.brandGradient, in: RoundedRectangle(cornerRadius: 14))
                                        }

                                        Button {
                                            resumeTimestamp = nil
                                            activePlayerDetail = detailWithPreferredSource(detail)
                                        } label: {
                                            Label("Prehrať od začiatku", systemImage: "arrow.counterclockwise")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .glassCard(cornerRadius: 14)
                                        }
                                    } else {
                                        Button {
                                            resumeTimestamp = nil
                                            activePlayerDetail = detailWithPreferredSource(detail)
                                        } label: {
                                            HStack {
                                                Image(systemName: "play.fill")
                                                Text("Prehrať v natívnom prehrávači")
                                                    .fontWeight(.bold)
                                            }
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 15)
                                            .background(AppTheme.brandGradient, in: RoundedRectangle(cornerRadius: 14))
                                        }
                                    }
                                }

                                // Action Row: Offline Download + Favorite
                                HStack(spacing: 12) {
                                    Button {
                                        guard let source = selectedSource ?? detail.bestSource else { return }
                                        downloads.startDownload(
                                            video: item,
                                            source: source,
                                            subtitles: detail.subtitles
                                        )
                                    } label: {
                                        let isDownloaded = downloads.completedDownload(for: item) != nil
                                        Label(
                                            isDownloaded ? "Stiahnuté offline" : "Stiahnuť do iPhonu",
                                            systemImage: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle.fill"
                                        )
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .glassCard(cornerRadius: 14)
                                    }

                                    Button {
                                        library.toggleFavorite(item)
                                    } label: {
                                        Label(
                                            library.isFavorite(item) ? "V obľúbených" : "Obľúbené",
                                            systemImage: library.isFavorite(item) ? "heart.fill" : "heart"
                                        )
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(library.isFavorite(item) ? AppTheme.brandPrimary : .white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .glassCard(cornerRadius: 14)
                                    }
                                }

                                // Stream Quality Picker
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Kvalita natívneho streamu")
                                        .font(.headline)
                                        .foregroundStyle(.white)

                                    ForEach(detail.sources) { source in
                                        Button {
                                            selectedSource = source
                                        } label: {
                                            HStack {
                                                Image(systemName: source.isPremiumOriginal ? "crown.fill" : "sparkles.tv")
                                                    .foregroundStyle(source.isPremiumOriginal ? AppTheme.premiumGold : AppTheme.brandPrimary)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(source.label)
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundStyle(.white)
                                                    Text(source.isPremiumOriginal ? "Nekomprimovaný originál cez Premium účet" : "Priamy MP4 CDN stream (\(source.resolution)p)")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                if selectedSource?.id == source.id {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(AppTheme.brandPrimary)
                                                }
                                            }
                                            .padding(12)
                                            .glassCard(cornerRadius: 12)
                                        }
                                    }
                                }

                                // Subtitles list
                                if !detail.subtitles.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Dostupné titulky")
                                            .font(.headline)
                                            .foregroundStyle(.white)

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(detail.subtitles) { sub in
                                                    Label(sub.label, systemImage: "captions.bubble")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(.white)
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 8)
                                                        .glassCard(cornerRadius: 10)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavrieť") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await loadStreams()
        }
        .fullScreenCover(item: $activePlayerDetail) { playerDetail in
            NativePlayerView(detail: playerDetail, resumeTime: resumeTimestamp)
        }
    }

    private func loadStreams() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await PrehrajToClient.shared.fetchVideoDetail(
                for: item,
                isPremiumLoggedIn: auth.isPremiumActive
            )
            detail = fetched
            selectedSource = fetched.bestSource
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func detailWithPreferredSource(_ original: VideoDetail) -> VideoDetail {
        guard let selectedSource else { return original }
        var reordered = original.sources.filter { $0.id != selectedSource.id }
        reordered.insert(selectedSource, at: 0)
        return VideoDetail(
            item: original.item,
            sources: reordered,
            subtitles: original.subtitles,
            descriptionText: original.descriptionText,
            viewsCount: original.viewsCount,
            uploadedDate: original.uploadedDate
        )
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }
}
