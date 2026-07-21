import AVFoundation
import SwiftUI

struct VigilPlaybackOverlay: View {
    let recording: VigilRecording
    let player: AVPlayer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("VIGIL CAPTURE")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(1.2)
                    Spacer()
                }

                Spacer()

                VStack(alignment: .leading, spacing: 3) {
                    Text(recording.utcTimestamp(at: elapsedTime))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    Text("UTC  •  ID \(recording.shortID)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
            .padding(20)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var elapsedTime: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(0, seconds) : 0
    }
}
