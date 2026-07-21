import AVFoundation

nonisolated final class VigilMovieRecorder: @unchecked Sendable {
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput
    private var hasStartedWriting = false
    private(set) var isRecording = true

    init(
        outputURL: URL,
        videoSettings: [String: Any],
        audioSettings: [String: Any],
        metadata: RecordingCaptureMetadata
    ) throws {
        assetWriter = try AVAssetWriter(url: outputURL, fileType: .mov)
        assetWriter.metadata = metadata.avMetadataItems

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        guard assetWriter.canAdd(videoInput), assetWriter.canAdd(audioInput) else {
            throw VigilMovieRecorderError.cannotConfigureWriter
        }
        assetWriter.add(videoInput)
        assetWriter.add(audioInput)
    }

    func recordVideo(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording else { return }

        if !hasStartedWriting {
            guard assetWriter.startWriting() else { return }
            assetWriter.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            hasStartedWriting = true
        }

        guard assetWriter.status == .writing, videoInput.isReadyForMoreMediaData else { return }
        videoInput.append(sampleBuffer)
    }

    func recordAudio(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              hasStartedWriting,
              assetWriter.status == .writing,
              audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }

    func stop(completion: @escaping (Result<URL, Error>) -> Void) {
        guard isRecording else { return }
        isRecording = false

        guard hasStartedWriting else {
            assetWriter.cancelWriting()
            completion(.failure(VigilMovieRecorderError.noVideoFrames))
            return
        }

        videoInput.markAsFinished()
        audioInput.markAsFinished()
        assetWriter.finishWriting { [self] in
            if self.assetWriter.status == .completed {
                completion(.success(self.assetWriter.outputURL))
            } else {
                completion(.failure(self.assetWriter.error ?? VigilMovieRecorderError.couldNotFinish))
            }
        }
    }
}

enum VigilMovieRecorderError: LocalizedError {
    case cannotConfigureWriter
    case noVideoFrames
    case couldNotFinish

    var errorDescription: String? {
        switch self {
        case .cannotConfigureWriter:
            "The dual-camera recording file could not be configured."
        case .noVideoFrames:
            "No dual-camera video frames were captured."
        case .couldNotFinish:
            "The dual-camera recording could not be finalized."
        }
    }
}
