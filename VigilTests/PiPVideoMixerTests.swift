import CoreImage
import Testing
@testable import Vigil

struct PiPVideoMixerTests {
    @Test(
        arguments: [
            CGSize(width: 720, height: 1280),
            CGSize(width: 1280, height: 720)
        ]
    )
    func matchingOrientationsDoNotRequireRotation(size: CGSize) {
        #expect(
            PiPVideoMixer.requiresQuarterTurn(
                sourceSize: size,
                canvasSize: size
            ) == false
        )
    }

    @Test(
        arguments: [
            (
                source: CGSize(width: 1280, height: 720),
                canvas: CGSize(width: 720, height: 1280)
            ),
            (
                source: CGSize(width: 720, height: 1280),
                canvas: CGSize(width: 1280, height: 720)
            )
        ]
    )
    func mismatchedOrientationsRequireRotation(
        sizes: (source: CGSize, canvas: CGSize)
    ) {
        #expect(
            PiPVideoMixer.requiresQuarterTurn(
                sourceSize: sizes.source,
                canvasSize: sizes.canvas
            )
        )
    }

    @Test func squareInputDoesNotInferAnOrientation() {
        #expect(
            PiPVideoMixer.requiresQuarterTurn(
                sourceSize: CGSize(width: 720, height: 720),
                canvasSize: CGSize(width: 720, height: 1280)
            ) == false
        )
    }

    @Test func normalizationRotatesAndReanchorsLandscapeInputForPortraitCanvas() {
        let source = CIImage(color: .red)
            .cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))

        let normalized = PiPVideoMixer.normalizedPictureInPicture(
            source,
            for: CGRect(x: 0, y: 0, width: 720, height: 1280)
        )

        #expect(normalized.extent == CGRect(x: 0, y: 0, width: 720, height: 1280))
    }
}
