import SwiftUI
import UIKit

struct CaptureView: View {
    @ObservedObject var model: VigilModel
    @ObservedObject var camera: CameraController
    @ObservedObject var screenCurtain: ScreenCurtainController
    @AppStorage(EmergencyCallHandoff.defaultsKey)
    private var emergencyNumber = EmergencyCallHandoff.defaultNumber
    @Environment(\.openURL) private var openURL
    @State private var controlRotation: Angle = .zero
    @State private var controlsAreLandscape = false
    @State private var landscapeStatusOnLeadingEdge = false
    let allowsScreenCurtainGesture: Bool
    let openSettings: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.readiness == .ready {
                CameraPreview(
                    camera: camera,
                    recordingMode: camera.selectedMode
                )
                    .ignoresSafeArea(edges: .top)
            } else if camera.readiness != .idle,
                      camera.readiness != .requestingPermission {
                unavailableView
            }

            LinearGradient(
                colors: [.black.opacity(0.72), .clear, .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if screenCurtain.isActive {
                Color.black
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                if screenCurtain.isActive {
                    Color.clear.frame(height: 50)
                } else {
                    header
                }
                Spacer()
                idlePrompt
                bottomControls
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 20)

            if showsCompactStatus {
                if controlsAreLandscape {
                    GeometryReader { geometry in
                        compactRecordingStatus
                            .frame(maxWidth: 190)
                            .position(
                                x: landscapeStatusOnLeadingEdge
                                    ? 36
                                    : geometry.size.width - 36,
                                y: geometry.size.height / 2
                            )
                    }
                    .ignoresSafeArea()
                } else {
                    VStack {
                        compactRecordingStatus
                            .frame(maxWidth: 190)
                        Spacer()
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
                }
            }
        }
        .task(id: model.captureNotice) {
            guard let notice = model.captureNotice,
                  notice.automaticallyClears else { return }
            try? await Task.sleep(for: .seconds(4))
            withAnimation { model.clearCaptureNotice(notice) }
        }
        .animation(.easeInOut(duration: 0.42), value: model.captureNotice)
        .animation(.easeInOut(duration: 0.38), value: camera.isRecording)
        .animation(.easeInOut(duration: 0.38), value: camera.isFinalizing)
        .animation(.easeInOut(duration: 0.38), value: camera.isChangingMode)
        .animation(.easeInOut(duration: 0.15), value: screenCurtain.isActive)
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            updateControlOrientation(UIDevice.current.orientation)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIDevice.orientationDidChangeNotification
            )
        ) { _ in
            updateControlOrientation(UIDevice.current.orientation)
        }
        .onChange(of: camera.isRecording) { _, isRecording in
            guard !isRecording else { return }
            updateControlOrientation(UIDevice.current.orientation)
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .background {
            ThreeFingerTripleTapRecognizer(
                isEnabled: screenCurtain.isGestureEnabled && allowsScreenCurtainGesture,
                onRecognized: screenCurtain.handleThreeFingerTripleTap
            )
            .frame(width: 0, height: 0)
        }
    }

    private var header: some View {
        HStack {
            Label("VIGIL", systemImage: "shield.lefthalf.filled")
                .font(.headline.weight(.black))
                .tracking(1.6)
            Spacer()
            Button(action: openSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.48), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(camera.isRecording || camera.isFinalizing)
            .opacity(camera.isRecording || camera.isFinalizing ? 0.45 : 1)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 10)
    }

    private var idlePrompt: some View {
        VStack(spacing: 7) {
            Text("Ready when you are")
                .font(.title3.weight(.semibold))
                .shadow(color: .black.opacity(0.75), radius: 3)

            Text("Tap once to begin recording")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .shadow(color: .black.opacity(0.85), radius: 3)
        }
        .frame(height: 94, alignment: .bottom)
        .opacity(
            camera.readiness == .ready
                && !showsCompactStatus
                && !screenCurtain.isActive
                && !controlsAreLandscape
                ? 1
                : 0
        )
        .animation(.easeInOut(duration: 0.35), value: showsCompactStatus)
        .animation(.easeInOut(duration: 0.35), value: controlsAreLandscape)
        .accessibilityHidden(showsCompactStatus || controlsAreLandscape)
    }

    private var showsCompactStatus: Bool {
        camera.isRecording
            || camera.isFinalizing
            || camera.isChangingMode
            || model.captureNotice != nil
            || screenCurtain.isActive
    }

    @ViewBuilder
    private var compactRecordingStatus: some View {
        Group {
            if camera.isRecording, let start = camera.recordingStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    landscapeStatusCapsule {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red)
                        Text(elapsed(from: start, to: context.date))
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    }
                }
            } else if camera.isFinalizing {
                landscapeStatusCapsule {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Saving…")
                }
            } else if camera.isChangingMode {
                landscapeStatusCapsule {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Switching camera…")
                }
            } else if let notice = model.captureNotice {
                landscapeStatusCapsule {
                    if notice.tone == .progress {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else if let icon = noticeIcon(for: notice.tone) {
                        Image(systemName: icon)
                            .foregroundStyle(noticeColor(for: notice.tone))
                    }
                    Text(notice.savedDestinations == nil ? notice.title : "Saved")
                        .foregroundStyle(noticeColor(for: notice.tone))
                }
            } else if screenCurtain.isActive {
                landscapeStatusCapsule {
                    Image(systemName: "eye.slash.fill")
                    Text("Screen Curtain")
                }
            }
        }
        .rotationEffect(controlRotation)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func landscapeStatusCapsule<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 7) {
            content()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.black.opacity(0.58), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
        .accessibilityElement(children: .combine)
    }

    private func noticeIcon(for tone: CaptureNotice.Tone) -> String? {
        switch tone {
        case .progress: nil
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .error: "xmark.circle.fill"
        case .information: "info.circle.fill"
        }
    }

    private func noticeColor(for tone: CaptureNotice.Tone) -> Color {
        switch tone {
        case .progress, .information: .white
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private var bottomControls: some View {
        ZStack {
            recordButton

            HStack {
                sosButton
                Spacer()
                if !screenCurtain.isActive {
                    recordingModeButton
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .padding(.top, 16)
    }

    private var sosButton: some View {
        Button {
            guard let phoneURL = EmergencyCallHandoff.phoneURL(for: emergencyNumber) else { return }
            openURL(phoneURL)
        } label: {
            Text("SOS")
                .font(.caption.weight(.black))
                .tracking(0.5)
                .foregroundStyle(.red)
                .rotationEffect(controlRotation)
                .frame(width: 54, height: 54)
                .background(.ultraThinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(EmergencyCallHandoff.phoneURL(for: emergencyNumber) == nil)
        .accessibilityLabel("Call emergency services")
        .accessibilityValue(emergencyNumber.isEmpty ? "Not configured" : emergencyNumber)
        .accessibilityHint("Opens the iPhone confirmation before calling")
    }

    private var recordButton: some View {
        Button {
            model.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 82, height: 82)
                RoundedRectangle(cornerRadius: camera.isRecording ? 7 : 34)
                    .fill(.red)
                    .frame(
                        width: camera.isRecording ? 32 : 66,
                        height: camera.isRecording ? 32 : 66
                    )
            }
            .frame(width: 100, height: 100)
            .contentShape(Circle())
        }
        .disabled(camera.readiness != .ready || camera.isChangingMode || camera.isFinalizing)
        .accessibilityLabel(camera.isRecording ? "Stop recording" : "Start recording")
    }

    private var recordingModeButton: some View {
        Button {
            camera.selectMode(nextRecordingMode)
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 54, height: 54)

                if camera.isChangingMode {
                    ProgressView()
                        .controlSize(.small)
                        .rotationEffect(controlRotation)
                } else {
                    Image(systemName: camera.selectedMode.systemImage)
                        .font(.system(size: 21, weight: .semibold))
                        .rotationEffect(controlRotation)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(camera.isRecording || camera.isChangingMode || camera.isFinalizing)
        .opacity(camera.isRecording ? 0.45 : 1)
        .accessibilityLabel("Change camera mode")
        .accessibilityValue(camera.selectedMode.title)
        .accessibilityHint("Switches to \(nextRecordingMode.title)")
    }

    private var nextRecordingMode: RecordingMode {
        switch camera.selectedMode {
        case .rear:
            .front
        case .front:
            camera.isDualCameraSupported ? .dual : .rear
        case .dual:
            .rear
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: statusIcon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(statusTitle)
                .font(.title3.weight(.semibold))
            Text(statusDetail)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 36)
        }
    }

    private func updateControlOrientation(_ orientation: UIDeviceOrientation) {
        guard !camera.isRecording else { return }

        let targetRotation: Angle
        let isLandscape: Bool
        let statusOnLeadingEdge: Bool

        switch orientation {
        case .portrait:
            targetRotation = .zero
            isLandscape = false
            statusOnLeadingEdge = false
        case .portraitUpsideDown:
            targetRotation = .degrees(180)
            isLandscape = false
            statusOnLeadingEdge = false
        case .landscapeLeft:
            targetRotation = .degrees(90)
            isLandscape = true
            statusOnLeadingEdge = false
        case .landscapeRight:
            targetRotation = .degrees(-90)
            isLandscape = true
            statusOnLeadingEdge = true
        case .faceUp, .faceDown, .unknown:
            return
        @unknown default:
            return
        }

        withAnimation(.easeInOut(duration: 0.35)) {
            controlRotation = targetRotation
            controlsAreLandscape = isLandscape
            landscapeStatusOnLeadingEdge = statusOnLeadingEdge
        }
    }

    private var statusIcon: String {
        switch camera.readiness {
        case .denied: "camera.fill.badge.ellipsis"
        case .unavailable: "iphone.gen3.slash"
        case .callInProgress: "phone.fill"
        case .failed: "exclamationmark.triangle"
        default: "camera"
        }
    }

    private var statusTitle: String {
        switch camera.readiness {
        case .idle, .requestingPermission: "Preparing Vigil…"
        case .denied: "Camera access is off"
        case .unavailable: "Camera unavailable"
        case .callInProgress: "Video unavailable during call"
        case .failed: "Camera could not start"
        case .ready: "Ready"
        }
    }

    private var statusDetail: String {
        switch camera.readiness {
        case .denied: "Allow camera and microphone access in Settings to record."
        case .unavailable: "The Simulator has no usable camera. Run Vigil on your iPhone to record."
        case .callInProgress:
            "Recording video is not available while on a call. Vigil will resume automatically when the call ends."
        case .failed(let message): message
        default: "Checking the camera and microphone."
        }
    }

    private func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
