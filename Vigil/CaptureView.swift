import SwiftUI

struct CaptureView: View {
    @ObservedObject var model: VigilModel
    @ObservedObject var camera: CameraController
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
            } else {
                unavailableView
            }

            LinearGradient(
                colors: [.black.opacity(0.72), .clear, .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                Spacer()
                recordingStatus
                bottomControls
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 20)
        }
        .overlay(alignment: .bottom) {
            if let message = model.bannerMessage {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 132)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(3))
                        if model.bannerMessage == message {
                            withAnimation { model.bannerMessage = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut, value: model.bannerMessage)
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

    @ViewBuilder
    private var recordingStatus: some View {
        if camera.isRecording, let start = camera.recordingStartedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 7) {
                    Text(elapsed(from: start, to: context.date))
                        .font(.system(size: 34, weight: .medium, design: .monospaced))
                    Label("RECORDING ON THIS IPHONE", systemImage: "record.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                }
            }
        } else {
            VStack(spacing: 6) {
                Text("Ready when you are")
                    .font(.title3.weight(.semibold))
                Text("Tap once to begin recording")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bottomControls: some View {
        ZStack {
            recordButton

            HStack {
                Spacer()
                recordingModeButton
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .padding(.top, 16)
    }

    private var recordButton: some View {
        Button {
            camera.isRecording ? camera.stopRecording() : camera.startRecording()
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
                } else {
                    Image(systemName: camera.selectedMode.systemImage)
                        .font(.system(size: 21, weight: .semibold))
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

    private var statusIcon: String {
        switch camera.readiness {
        case .denied: "camera.fill.badge.ellipsis"
        case .unavailable: "iphone.gen3.slash"
        case .failed: "exclamationmark.triangle"
        default: "camera"
        }
    }

    private var statusTitle: String {
        switch camera.readiness {
        case .idle, .requestingPermission: "Preparing Vigil…"
        case .denied: "Camera access is off"
        case .unavailable: "Camera unavailable"
        case .failed: "Camera could not start"
        case .ready: "Ready"
        }
    }

    private var statusDetail: String {
        switch camera.readiness {
        case .denied: "Allow camera and microphone access in Settings to record."
        case .unavailable: "The Simulator has no usable camera. Run Vigil on your iPhone to record."
        case .failed(let message): message
        default: "Checking the camera and microphone."
        }
    }

    private func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
