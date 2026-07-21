import SwiftUI

struct CaptureView: View {
    @ObservedObject var model: VigilModel
    @ObservedObject var camera: CameraController
    @ObservedObject var screenCurtain: ScreenCurtainController
    @Environment(\.openURL) private var openURL
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
                recordingStatus
                bottomControls
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 20)
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

    @ViewBuilder
    private var recordingStatus: some View {
        VStack(spacing: 7) {
            if camera.isRecording, let start = camera.recordingStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsed(from: start, to: context.date))
                        .font(.system(size: 34, weight: .medium, design: .monospaced))
                        .shadow(color: .black.opacity(0.75), radius: 3)
                }
                .transition(.opacity)
            } else if screenCurtain.isActive {
                Text("Screen Curtain")
                    .font(.title3.weight(.semibold))
                    .shadow(color: .black.opacity(0.75), radius: 3)
                    .transition(.opacity)
            } else if model.captureNotice == nil,
                      !camera.isFinalizing,
                      !camera.isChangingMode,
                      camera.readiness == .ready {
                Text("Ready when you are")
                    .font(.title3.weight(.semibold))
                    .shadow(color: .black.opacity(0.75), radius: 3)
                    .transition(.opacity)
            } else {
                Color.clear
                    .frame(height: 28)
                    .transition(.opacity)
            }

            if camera.isRecording {
                statusLine(
                    recordingLine,
                    icon: "circle.fill",
                    color: .red
                )
            } else if camera.isFinalizing {
                statusLine("Saving recording…", color: .white, showsProgress: true)
            } else if camera.isChangingMode {
                statusLine("Switching camera…", color: .white, showsProgress: true)
            } else if let notice = model.captureNotice {
                if let destinations = notice.savedDestinations {
                    savedDestinationsLine(destinations)
                } else {
                    statusLine(
                        notice.title,
                        icon: noticeIcon(for: notice.tone),
                        color: noticeColor(for: notice.tone),
                        showsProgress: notice.tone == .progress
                    )
                }
            } else if screenCurtain.isActive {
                statusLine(
                    "Triple-tap to reveal",
                    icon: "eye.slash.fill",
                    color: .white
                )
            } else if camera.readiness == .ready {
                statusLine("Tap once to begin recording", color: .secondary)
            }
        }
        .frame(height: 94, alignment: .bottom)
    }

    private var recordingLine: String {
        guard let notice = model.captureNotice,
              notice.tone == .success else { return "Recording" }
        return "Recording · \(notice.title)"
    }

    private func statusLine(
        _ text: String,
        icon: String? = nil,
        color: Color,
        showsProgress: Bool = false
    ) -> some View {
        ZStack {
            HStack(spacing: 8) {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(color)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                }

                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .id(text)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, minHeight: 20)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color)
        .shadow(color: .black.opacity(0.85), radius: 3)
        .animation(.easeInOut(duration: 0.42), value: text)
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }

    private func savedDestinationsLine(_ destinations: [String]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold))

            Text("Saved to Vault")

            ForEach(destinations.filter { $0 != "Vault" }, id: \.self) { destination in
                Text("+ \(destination)")
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(x: -6)),
                            removal: .opacity
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 20)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.green)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .shadow(color: .black.opacity(0.85), radius: 3)
        .animation(.easeInOut(duration: 0.5), value: destinations)
        .accessibilityElement(children: .combine)
        .transition(.opacity)
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
            guard let phoneURL = EmergencyCallHandoff.phoneURL else { return }
            openURL(phoneURL)
        } label: {
            Text("SOS")
                .font(.caption.weight(.black))
                .tracking(0.5)
                .foregroundStyle(.red)
                .frame(width: 54, height: 54)
                .background(.ultraThinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Call emergency services")
        .accessibilityValue(EmergencyCallHandoff.number)
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
