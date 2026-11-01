import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// Hardware-accelerated native AVPlayerLayer view supporting Picture-in-Picture (`AVPictureInPictureController`).
struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let isAspectFill: Bool
    @Binding var isPiPActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = isAspectFill ? .resizeAspectFill : .resizeAspect
        context.coordinator.setupPiP(with: view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = isAspectFill ? .resizeAspectFill : .resizeAspect
        context.coordinator.updatePiPState(isActive: isPiPActive)
    }

    final class PlayerLayerUIView: UIView {
        override static var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }
    }

    final class Coordinator: NSObject, AVPictureInPictureControllerDelegate {
        var parent: AVPlayerLayerView
        private var pipController: AVPictureInPictureController?

        init(_ parent: AVPlayerLayerView) {
            self.parent = parent
        }

        func setupPiP(with layer: AVPlayerLayer) {
            guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
            pipController = AVPictureInPictureController(playerLayer: layer)
            pipController?.delegate = self
            if #available(iOS 14.2, *) {
                pipController?.canStartPictureInPictureAutomaticallyFromInline = true
            }
        }

        func updatePiPState(isActive: Bool) {
            guard let pip = pipController else { return }
            if isActive && !pip.isPictureInPictureActive {
                pip.startPictureInPicture()
            } else if !isActive && pip.isPictureInPictureActive {
                pip.stopPictureInPicture()
            }
        }

        func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            DispatchQueue.main.async {
                self.parent.isPiPActive = true
            }
        }

        func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            DispatchQueue.main.async {
                self.parent.isPiPActive = false
            }
        }
    }
}

/// Native iOS AirPlay route picker button (`AVRoutePickerView`).
struct AirPlayButtonView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(red: 0.95, green: 0.22, blue: 0.32, alpha: 1.0)
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
