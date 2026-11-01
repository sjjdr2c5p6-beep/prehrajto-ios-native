import SwiftUI

struct VideoCardView: View {
    let item: VideoItem
    var progress: WatchProgressItem? = nil
    var onTap: () -> Void

    @ObservedObject private var library = LibraryManager.shared

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Thumbnail with badges
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: item.thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16 / 9, contentMode: .fill)
                        default:
                            ZStack {
                                AppTheme.backgroundSecondary
                                Image(systemName: "play.tv.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                            .aspectRatio(16 / 9, contentMode: .fill)
                        }
                    }
                    .frame(height: 112)
                    .clipped()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Top-right HD badge & Favorite indicator
                    VStack {
                        HStack {
                            if item.isHD {
                                Text("HD")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(AppTheme.brandGradient, in: RoundedRectangle(cornerRadius: 5))
                            }
                            Spacer()
                            if library.isFavorite(item) {
                                Image(systemName: "heart.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.brandPrimary)
                                    .padding(5)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }
                        Spacer()
                    }
                    .padding(8)

                    // Bottom metadata row (Duration + Size)
                    HStack {
                        Label(item.duration, systemImage: "clock")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5))

                        Spacer()

                        if !item.fileSize.isEmpty {
                            Text(item.fileSize)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    .padding(8)

                    // Watch Progress Bar at bottom of thumbnail
                    if let progress {
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.25))
                                        .frame(height: 4)
                                    Rectangle()
                                        .fill(AppTheme.brandPrimary)
                                        .frame(width: geo.size.width * progress.progressFraction, height: 4)
                                }
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let progress {
                        Text(progress.remainingTimeFormatted)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.brandSecondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
            .padding(8)
            .glassCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }
}
