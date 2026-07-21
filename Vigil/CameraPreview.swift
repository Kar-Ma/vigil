import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let camera: CameraController
    let recordingMode: RecordingMode

    func makeUIView(context: Context) -> CameraPreviewContainerView {
        let view = CameraPreviewContainerView()
        view.attach(
            primary: camera.primaryPreviewLayer,
            secondary: camera.secondaryPreviewLayer
        )
        view.updateLayout(for: recordingMode)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewContainerView, context: Context) {
        uiView.updateLayout(for: recordingMode)
    }
}

final class CameraPreviewContainerView: UIView {
    private var recordingMode: RecordingMode = .rear

    private weak var primaryLayer: AVCaptureVideoPreviewLayer?
    private weak var secondaryLayer: AVCaptureVideoPreviewLayer?

    func attach(primary: AVCaptureVideoPreviewLayer, secondary: AVCaptureVideoPreviewLayer) {
        primary.removeFromSuperlayer()
        secondary.removeFromSuperlayer()
        layer.addSublayer(primary)
        layer.addSublayer(secondary)
        primaryLayer = primary
        secondaryLayer = secondary
        secondary.masksToBounds = true
        secondary.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
    }

    func updateLayout(for mode: RecordingMode) {
        recordingMode = mode

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primaryLayer?.isHidden = mode == .front
        secondaryLayer?.isHidden = mode == .rear
        secondaryLayer?.cornerRadius = mode == .dual ? 14 : 0
        secondaryLayer?.borderWidth = mode == .dual ? 2 : 0
        setNeedsLayout()
        layoutIfNeeded()
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        primaryLayer?.frame = bounds

        if recordingMode == .dual {
            let width = bounds.width * 0.29
            let height = bounds.height * 0.25
            let margin = bounds.width * 0.045
            secondaryLayer?.frame = CGRect(
                x: bounds.maxX - width - margin,
                y: safeAreaInsets.top + 68,
                width: width,
                height: height
            )
        } else {
            secondaryLayer?.frame = bounds
        }
    }
}
