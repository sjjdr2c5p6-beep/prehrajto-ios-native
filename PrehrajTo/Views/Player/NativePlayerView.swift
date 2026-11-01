import AVKit
import SwiftUI

struct NativePlayerView: View {
    let detail: VideoDetail
    let resumeTime: Double?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PlayerViewModel()
    @ObservedObject private var library = LibraryManager.shared

    @State private var showControls: Bool = true
    @State private var isScrubbing: Bool = false
    @State private var scrubValue: Double = 0.0
    @State private var showSubtitlesSheet: Bool = false
    @State private var skipRippleDirection: Int? = nil // -10 or +10
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // 1. Hardware-Accelerated Native AVPlayerLayer
                AVPlayerLayerView(
                    player: viewModel.player,
                    isAspectFill: viewModel.isAspectFill,
                    isPiPActive: $viewModel.isPiPActive
                )
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleControls()
                }
                .overlay(
                    HStack(spacing: 0) {
                        // Left zone double-tap (-10s)
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                triggerSkip(seconds: -10)
                            }
                            .onTapGesture(count: 1) {
                                toggleControls()
                            }

                        // Right zone double-tap (+10s)
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                triggerSkip(seconds: 10)
                            }
                            .onTapGesture(count: 1) {
                                toggleControls()
                            }
                    }
                )

                // 2. Double-Tap Skip Ripple Indicator
                if let direction = skipRippleDirection {
                    HStack {
                        if direction > 0 { Spacer() }
                        VStack(spacing: 6) {
                            Image(systemName: direction < 0 ? "gobackward.10" : "goforward.10")
                                .font(.system(size: 36, weight: .bold))
                            Text(direction < 0 ? "-10 sekúnd" : "+10 sekúnd")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(.white)
                        .padding(24)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(.horizontal, 60)
                        if direction < 0 { Spacer() }
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                // 3. Synchronized Native WebVTT Subtitles Overlay
                if let subtitleText = viewModel.activeSubtitleText, !subtitleText.isEmpty {
                    VStack {
                        Spacer()
                        Text(subtitleText)
                            .font(.system(size: viewModel.subtitleFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal, 28)
                            .padding(.bottom, showControls ? 110 : 34)
                            .animation(.easeInOut(duration: 0.2), value: showControls)
                    }
                    .allowsHitTesting(false)
                }

                // 4. Buffering Spinner or Error State
                if viewModel.isBuffering {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppTheme.brandPrimary)
                        .scaleEffect(1.5)
                        .padding(22)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                if let error = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Button("Skúsiť znova") {
                            if let source = viewModel.selectedSource {
                                viewModel.selectSource(source)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.brandPrimary)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding()
                }

                // 5. Modern Glass OSD Controls Overlay
                if showControls {
                    controlsOverlay
                        .transition(.opacity)
                }
            }
        }
        .statusBarHidden(!showControls)
        .onAppear {
            viewModel.loadVideo(detail: detail, resumeFrom: resumeTime)
            scheduleHideControls()
        }
        .onDisappear {
            hideControlsTask?.cancel()
            viewModel.cleanup()
        }
        .sheet(isPresented: $showSubtitlesSheet) {
            subtitleCustomizationSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.75),
                    Color.black.opacity(0.20),
                    Color.black.opacity(0.80)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                // Top Bar
                HStack(spacing: 14) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            if let source = viewModel.selectedSource {
                                Text(source.badgeText)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(source.isPremiumOriginal ? AppTheme.premiumGold : AppTheme.brandPrimary)
                            }
                            if let sub = viewModel.selectedSubtitleTrack {
                                Text("• Titulky: \(sub.language.uppercased())")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }

                    Spacer()

                    // AirPlay Native Route Picker
                    AirPlayButtonView()
                        .frame(width: 36, height: 36)

                    // Picture-in-Picture Toggle
                    if AVPictureInPictureController.isPictureInPictureSupported() {
                        Button {
                            viewModel.isPiPActive.toggle()
                        } label: {
                            Image(systemName: viewModel.isPiPActive ? "pip.exit" : "pip.enter")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }

                    // Aspect Ratio Toggle (Fit / Fill)
                    Button {
                        viewModel.isAspectFill.toggle()
                        scheduleHideControls()
                    } label: {
                        Image(systemName: viewModel.isAspectFill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                // Center Transport Buttons
                HStack(spacing: 48) {
                    Button {
                        viewModel.skip(by: -10)
                        scheduleHideControls()
                    } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Button {
                        viewModel.togglePlayPause()
                        scheduleHideControls()
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 74, height: 74)
                            .background(AppTheme.brandGradient, in: Circle())
                            .shadow(color: AppTheme.brandPrimary.opacity(0.5), radius: 14)
                    }

                    Button {
                        viewModel.skip(by: 10)
                        scheduleHideControls()
                    } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }

                Spacer()

                // Bottom Bar: Timeline Scrubber + Quality, Subtitles, Speed
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Text(formatTime(isScrubbing ? scrubValue : viewModel.currentTime))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white)

                        Slider(
                            value: Binding(
                                get: { isScrubbing ? scrubValue : viewModel.currentTime },
                                set: { newVal in scrubValue = newVal }
                            ),
                            in: 0...max(viewModel.duration, 1),
                            onEditingChanged: { editing in
                                isScrubbing = editing
                                if editing {
                                    hideControlsTask?.cancel()
                                } else {
                                    viewModel.seek(to: scrubValue)
                                    scheduleHideControls()
                                }
                            }
                        )
                        .tint(AppTheme.brandPrimary)

                        Text(formatTime(viewModel.duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    HStack(spacing: 12) {
                        // Quality Menu
                        Menu {
                            ForEach(detail.sources) { source in
                                Button {
                                    viewModel.selectSource(source)
                                } label: {
                                    HStack {
                                        Text(source.label)
                                        if viewModel.selectedSource?.id == source.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label(viewModel.selectedSource?.label ?? "Kvalita", systemImage: "sparkles.tv")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                        }

                        // Subtitles Button
                        Button {
                            showSubtitlesSheet = true
                        } label: {
                            Label(
                                viewModel.selectedSubtitleTrack?.language.uppercased() ?? "Titulky",
                                systemImage: viewModel.selectedSubtitleTrack == nil ? "captions.bubble" : "captions.bubble.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                        }

                        // Playback Speed Menu
                        Menu {
                            ForEach([Float(0.5), 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                                Button {
                                    viewModel.setPlaybackSpeed(rate)
                                } label: {
                                    HStack {
                                        Text("\(String(format: "%.2g", rate))×")
                                        if viewModel.playbackSpeed == rate {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("\(String(format: "%.2g", viewModel.playbackSpeed))×", systemImage: "speedometer")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                        }

                        Spacer()

                        // Favorite Button inside Player
                        Button {
                            library.toggleFavorite(detail.item)
                        } label: {
                            Image(systemName: library.isFavorite(detail.item) ? "heart.fill" : "heart")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(library.isFavorite(detail.item) ? AppTheme.brandPrimary : .white)
                                .frame(width: 34, height: 34)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Subtitles Customization Sheet

    private var subtitleCustomizationSheet: some View {
        NavigationStack {
            List {
                Section("Dostupné titulky (.VTT)") {
                    Button {
                        viewModel.selectSubtitle(nil)
                    } label: {
                        HStack {
                            Text("Vypnuté")
                                .foregroundStyle(.white)
                            Spacer()
                            if viewModel.selectedSubtitleTrack == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppTheme.brandPrimary)
                            }
                        }
                    }

                    ForEach(detail.subtitles) { track in
                        Button {
                            viewModel.selectSubtitle(track)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(track.label)
                                        .foregroundStyle(.white)
                                    Text(track.language.uppercased())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if viewModel.selectedSubtitleTrack?.id == track.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.brandPrimary)
                                }
                            }
                        }
                    }
                }

                Section("Synchronizácia a vzhľad") {
                    HStack {
                        Text("Posun titulkov")
                        Spacer()
                        Button("-0.5s") { viewModel.subtitleOffset -= 0.5 }
                            .buttonStyle(.bordered)
                        Text(String(format: "%+.1fs", viewModel.subtitleOffset))
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 56)
                        Button("+0.5s") { viewModel.subtitleOffset += 0.5 }
                            .buttonStyle(.bordered)
                    }

                    HStack {
                        Text("Veľkosť písma")
                        Slider(value: $viewModel.subtitleFontSize, in: 14...28, step: 1)
                            .tint(AppTheme.brandPrimary)
                        Text("\(Int(viewModel.subtitleFontSize)) pt")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
            .navigationTitle("Nastavenia titulkov")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .ConfirmationAction) {
                    Button("Hotovo") { showSubtitlesSheet = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Helpers

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            scheduleHideControls()
        }
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            guard !Task.isCancelled, viewModel.isPlaying, !isScrubbing else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showControls = false
                }
            }
        }
    }

    private func triggerSkip(seconds: Double) {
        viewModel.skip(by: seconds)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            skipRippleDirection = Int(seconds)
        }
        Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            await MainActor.run {
                withAnimation {
                    skipRippleDirection = nil
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
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

private extension ToolbarItemPlacement {
    static var ConfirmationAction: ToolbarItemPlacement { .confirmationAction }
}
