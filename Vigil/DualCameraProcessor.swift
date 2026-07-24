import AVFoundation

nonisolated final class DualCameraProcessor: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate,
    @unchecked Sendable {
    let backVideoOutput = AVCaptureVideoDataOutput()
    let frontVideoOutput = AVCaptureVideoDataOutput()
    let audioOutput = AVCaptureAudioDataOutput()

    private let outputQueue = DispatchQueue(label: "com.karthikmahadevan.vigil.dual-camera-output")
    private let mixer = PiPVideoMixer()
    private var currentFrontSampleBuffer: CMSampleBuffer?
    private var recorder: VigilMovieRecorder?
    private var recordingMode: RecordingMode = .rear

    override init() {
        super.init()

        let videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        backVideoOutput.videoSettings = videoSettings
        frontVideoOutput.videoSettings = videoSettings
        backVideoOutput.alwaysDiscardsLateVideoFrames = true
        frontVideoOutput.alwaysDiscardsLateVideoFrames = true

        backVideoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        frontVideoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        audioOutput.setSampleBufferDelegate(self, queue: outputQueue)
    }

    func reset() {
        outputQueue.sync {
            currentFrontSampleBuffer = nil
            recorder = nil
            mixer.reset()
        }
    }

    func setMode(_ mode: RecordingMode) {
        outputQueue.sync {
            recordingMode = mode
            currentFrontSampleBuffer = nil
        }
    }

    func startRecording(to outputURL: URL, metadata: RecordingCaptureMetadata) throws {
        try outputQueue.sync {
            let activeVideoOutput = recordingMode == .front ? frontVideoOutput : backVideoOutput
            guard let videoSettings = activeVideoOutput.recommendedVideoSettingsForAssetWriter(
                writingTo: .mov
            ),
            let audioSettings = audioOutput.recommendedAudioSettingsForAssetWriter(
                writingTo: .mov
            ) else {
                throw DualCameraProcessorError.missingWriterSettings
            }

            currentFrontSampleBuffer = nil
            mixer.reset()
            recorder = try VigilMovieRecorder(
                outputURL: outputURL,
                videoSettings: videoSettings,
                audioSettings: audioSettings,
                metadata: metadata
            )
        }
    }

    func stopRecording(completion: @escaping (Result<URL, Error>) -> Void) {
        outputQueue.async { [weak self] in
            guard let self, let recorder = self.recorder else {
                completion(.failure(DualCameraProcessorError.notRecording))
                return
            }
            self.recorder = nil
            recorder.stop(completion: completion)
        }
    }

    private func processBackVideo(_ sampleBuffer: CMSampleBuffer) {
        if recordingMode == .rear {
            recorder?.recordVideo(sampleBuffer)
            return
        }
        guard recordingMode == .dual else { return }

        guard let fullScreenBuffer = sampleBuffer.imageBuffer,
              let frontSampleBuffer = currentFrontSampleBuffer,
              let frontBuffer = frontSampleBuffer.imageBuffer,
              let formatDescription = sampleBuffer.formatDescription else { return }

        if mixer.outputFormatDescription == nil, !mixer.prepare(using: formatDescription) {
            return
        }

        guard let mixedBuffer = mixer.mix(
            fullScreen: fullScreenBuffer,
            pictureInPicture: frontBuffer
        ),
        let outputDescription = mixer.outputFormatDescription,
        let mixedSampleBuffer = makeSampleBuffer(
            from: mixedBuffer,
            formatDescription: outputDescription,
            presentationTime: sampleBuffer.presentationTimeStamp
        ) else { return }

        recorder?.recordVideo(mixedSampleBuffer)
    }

    private func makeSampleBuffer(
        from pixelBuffer: CVPixelBuffer,
        formatDescription: CMFormatDescription,
        presentationTime: CMTime
    ) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return status == noErr ? sampleBuffer : nil
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output === frontVideoOutput {
            currentFrontSampleBuffer = sampleBuffer
            if recordingMode == .front {
                recorder?.recordVideo(sampleBuffer)
            }
        } else if output === backVideoOutput {
            processBackVideo(sampleBuffer)
        } else if output === audioOutput {
            recorder?.recordAudio(sampleBuffer)
        }
    }
}

enum DualCameraProcessorError: LocalizedError {
    case missingWriterSettings
    case notRecording

    var errorDescription: String? {
        switch self {
        case .missingWriterSettings:
            "Vigil could not prepare the dual-camera recording format."
        case .notRecording:
            "There was no dual-camera recording to finish."
        }
    }
}
