import AVFoundation
import CoreImage
import CoreText
import Foundation
import UIKit

@MainActor
enum VigilStampedVideoExporter {
    static func export(_ recording: VigilRecording) async throws -> URL {
        let asset = AVURLAsset(url: recording.url)
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VigilStampedExportError.cannotCreateExporter
        }

        let renderer = VigilStampFrameRenderer(
            startedAt: recording.createdAt,
            shortID: recording.shortID
        )
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let source = request.sourceImage
            let seconds = request.compositionTime.seconds
            guard let stamp = renderer.image(
                frameSize: source.extent.size,
                elapsedTime: seconds.isFinite ? max(0, seconds) : 0
            ) else {
                request.finish(with: source, context: nil)
                return
            }

            let margin = max(18, source.extent.width * 0.035)
            let positionedStamp = stamp.transformed(
                by: CGAffineTransform(
                    translationX: source.extent.minX + margin,
                    y: source.extent.minY + margin
                )
            )
            request.finish(with: positionedStamp.composited(over: source), context: nil)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vigil-stamped-\(recording.shortID.lowercased())-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.videoComposition = composition
        exportSession.metadata = try await asset.load(.metadata)
        exportSession.shouldOptimizeForNetworkUse = true
        try await exportSession.export(to: outputURL, as: .mov)
        return outputURL
    }
}

private nonisolated final class VigilStampFrameRenderer: @unchecked Sendable {
    private let startedAt: Date
    private let shortID: String
    private let lock = NSLock()
    private var cachedSecond = -1
    private var cachedWidth = 0
    private var cachedImage: CIImage?

    init(startedAt: Date, shortID: String) {
        self.startedAt = startedAt
        self.shortID = shortID
    }

    func image(frameSize: CGSize, elapsedTime: TimeInterval) -> CIImage? {
        let second = max(0, Int(elapsedTime.rounded(.down)))
        let width = Int(min(900, max(360, frameSize.width * 0.55)))

        lock.lock()
        defer { lock.unlock() }
        if second == cachedSecond, width == cachedWidth, let cachedImage {
            return cachedImage
        }

        let timestamp = utcTimestamp(for: startedAt.addingTimeInterval(TimeInterval(second)))
        let newImage = render(width: width, timestamp: timestamp)
        cachedSecond = second
        cachedWidth = width
        cachedImage = newImage
        return newImage
    }

    private func render(width: Int, timestamp: String) -> CIImage? {
        let height = max(126, Int(Double(width) * 0.28))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let scale = CGFloat(width) / 540
        let canvasHeight = CGFloat(height)
        let backgroundRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: canvasHeight)
        context.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.025, alpha: 0.72))
        context.addPath(CGPath(roundedRect: backgroundRect, cornerWidth: 18 * scale, cornerHeight: 18 * scale, transform: nil))
        context.fillPath()

        context.setFillColor(CGColor(red: 1, green: 0.16, blue: 0.2, alpha: 1))
        let recordingDotRect = CGRect(
            x: 24 * scale,
            y: canvasHeight - (43 * scale),
            width: 13 * scale,
            height: 13 * scale
        )
        context.fillEllipse(in: recordingDotRect)

        draw(
            "VIGIL CAPTURE",
            in: context,
            at: CGPoint(x: 49 * scale, y: canvasHeight - (50 * scale)),
            size: 22 * scale
        )
        draw(
            timestamp,
            in: context,
            at: CGPoint(x: 24 * scale, y: canvasHeight - (95 * scale)),
            size: 25 * scale,
            monospaced: true
        )
        draw(
            "UTC  •  VIGIL-STAMPED COPY  •  ID \(shortID)",
            in: context,
            at: CGPoint(x: 24 * scale, y: 19 * scale),
            size: 13 * scale,
            opacity: 0.82,
            monospaced: true
        )

        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    private func draw(
        _ text: String,
        in context: CGContext,
        at point: CGPoint,
        size: CGFloat,
        opacity: CGFloat = 1,
        monospaced: Bool = false
    ) {
        let fontName = monospaced ? "SFMono-Semibold" : "HelveticaNeue-Bold"
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(gray: 1, alpha: opacity)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private func utcTimestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

enum VigilStampedExportError: LocalizedError {
    case cannotCreateExporter

    var errorDescription: String? {
        "Vigil could not prepare a stamped copy of this recording."
    }
}
