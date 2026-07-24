import AVFoundation
import CoreImage

nonisolated final class PiPVideoMixer {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var outputPool: CVPixelBufferPool?
    private(set) var outputFormatDescription: CMFormatDescription?
    private var dimensions = CMVideoDimensions()

    func reset() {
        outputPool = nil
        outputFormatDescription = nil
        dimensions = CMVideoDimensions()
    }

    func prepare(using formatDescription: CMFormatDescription) -> Bool {
        reset()
        dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        guard dimensions.width > 0, dimensions.height > 0 else { return false }

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(dimensions.width),
            kCVPixelBufferHeightKey as String: Int(dimensions.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            [kCVPixelBufferPoolMinimumBufferCountKey as String: 4] as CFDictionary,
            attributes as CFDictionary,
            &pool
        ) == kCVReturnSuccess, let pool else { return false }

        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return false }

        var outputDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &outputDescription
        ) == noErr else { return false }

        outputPool = pool
        outputFormatDescription = outputDescription
        return true
    }

    func mix(fullScreen: CVPixelBuffer, pictureInPicture: CVPixelBuffer) -> CVPixelBuffer? {
        guard let outputPool else { return nil }
        var outputBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPool, &outputBuffer) == kCVReturnSuccess,
              let outputBuffer else { return nil }

        let fullImage = CIImage(cvPixelBuffer: fullScreen)
        let canvas = fullImage.extent
        let pipImage = Self.normalizedPictureInPicture(
            CIImage(cvPixelBuffer: pictureInPicture),
            for: canvas
        )

        let pipWidth = canvas.width * 0.29
        let pipHeight = canvas.height * 0.25
        let margin = canvas.width * 0.045
        let pipRect = CGRect(
            x: canvas.maxX - pipWidth - margin,
            y: canvas.maxY - pipHeight - margin,
            width: pipWidth,
            height: pipHeight
        )

        let scale = max(pipRect.width / pipImage.extent.width, pipRect.height / pipImage.extent.height)
        let scaledPip = pipImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let positionedPip = scaledPip
            .transformed(by: CGAffineTransform(
                translationX: pipRect.midX - scaledPip.extent.midX,
                y: pipRect.midY - scaledPip.extent.midY
            ))
            .cropped(to: pipRect.insetBy(dx: 3, dy: 3))

        let border = CIImage(color: .black).cropped(to: pipRect)
        let composed = positionedPip
            .composited(over: border)
            .composited(over: fullImage)
            .cropped(to: canvas)

        context.render(composed, to: outputBuffer, bounds: canvas, colorSpace: colorSpace)
        return outputBuffer
    }

    static func normalizedPictureInPicture(_ image: CIImage, for canvas: CGRect) -> CIImage {
        guard requiresQuarterTurn(sourceSize: image.extent.size, canvasSize: canvas.size) else {
            return image
        }

        let rotatedImage = image.transformed(
            by: CGAffineTransform(rotationAngle: .pi / 2)
        )
        return rotatedImage.transformed(
            by: CGAffineTransform(
                translationX: -rotatedImage.extent.minX,
                y: -rotatedImage.extent.minY
            )
        )
    }

    static func requiresQuarterTurn(sourceSize: CGSize, canvasSize: CGSize) -> Bool {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              canvasSize.width > 0,
              canvasSize.height > 0 else {
            return false
        }

        guard sourceSize.width != sourceSize.height,
              canvasSize.width != canvasSize.height else {
            return false
        }

        let sourceIsPortrait = sourceSize.height > sourceSize.width
        let canvasIsPortrait = canvasSize.height > canvasSize.width
        return sourceIsPortrait != canvasIsPortrait
    }
}
