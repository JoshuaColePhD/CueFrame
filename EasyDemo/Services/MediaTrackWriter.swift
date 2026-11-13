import AVFoundation

/// Access is confined to the recording session's serial sample queue.
final class MediaTrackWriter {
    let url: URL
    private let writer: AVAssetWriter
    private var input: AVAssetWriterInput?
    private(set) var sampleCount = 0
    private var lastTime = CMTime.invalid
    private var lastVideoSample: CMSampleBuffer?
    private var lastAudioEnd = CMTime.invalid

    init(url: URL) throws {
        self.url = url
        writer = try AVAssetWriter(url: url, fileType: .mov)
    }

    func append(_ sample: CMSampleBuffer, origin: CMTime, video: Bool) throws {
        guard sample.isValid, CMSampleBufferDataIsReady(sample) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sample) - origin
        guard time.isNumeric, time >= .zero else { return }
        if lastTime.isValid && time <= lastTime { return }
        if !video, lastAudioEnd.isNumeric, (time - lastAudioEnd).seconds > 0.1 {
            throw EditingError.media("Audio capture was interrupted. The recording has stopped to preserve synchronization.")
        }
        if input == nil {
            guard let description = sample.formatDescription else { return }
            let settings: [String: Any]
            if video {
                let size = CMVideoFormatDescriptionGetDimensions(description)
                settings = [AVVideoCodecKey: AVVideoCodecType.hevc,
                            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
                            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(4_000_000, Int(size.width) * Int(size.height) * 4)]]
            } else {
                guard let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { return }
                settings = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                            AVNumberOfChannelsKey: min(2, Int(format.mChannelsPerFrame)), AVEncoderBitRateKey: 192_000]
            }
            guard writer.canApply(outputSettings: settings, forMediaType: video ? .video : .audio) else {
                throw EditingError.media("The encoder does not support this capture format.")
            }
            let value = AVAssetWriterInput(mediaType: video ? .video : .audio, outputSettings: settings, sourceFormatHint: description)
            value.expectsMediaDataInRealTime = true
            guard writer.canAdd(value) else { throw EditingError.media("Could not create a media track.") }
            writer.add(value); input = value
            guard writer.startWriting() else { throw writer.error ?? EditingError.media("Could not start writing media.") }
            writer.startSession(atSourceTime: .zero)
        }
        guard let input else { return }
        guard writer.status == .writing else { throw writer.error ?? EditingError.media("Media writing stopped unexpectedly.") }
        if !video && !input.isReadyForMoreMediaData {
            let deadline = Date().addingTimeInterval(0.1)
            while !input.isReadyForMoreMediaData && writer.status == .writing && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
        }
        guard input.isReadyForMoreMediaData else {
            // Dropped video frames are recoverable; dropping narration is not.
            if video { return }
            throw EditingError.media("Audio could not be saved fast enough. The recording has been stopped to preserve its tracks.")
        }
        var count = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count) == noErr else {
            throw EditingError.media("Could not read media timestamps.")
        }
        for i in timing.indices {
            if timing[i].presentationTimeStamp.isValid { timing[i].presentationTimeStamp = timing[i].presentationTimeStamp - origin }
            if timing[i].decodeTimeStamp.isValid { timing[i].decodeTimeStamp = timing[i].decodeTimeStamp - origin }
        }
        var adjusted: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample,
                sampleTimingEntryCount: timing.count, sampleTimingArray: &timing, sampleBufferOut: &adjusted) == noErr,
              let adjusted, input.append(adjusted) else {
            throw writer.error ?? EditingError.media("Could not save a media sample.")
        }
        sampleCount += 1; lastTime = time
        if video { lastVideoSample = adjusted }
        else if let description = sample.formatDescription,
                let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
            lastAudioEnd = time + CMTime(seconds: Double(CMSampleBufferGetNumSamples(sample)) / format.mSampleRate, preferredTimescale: 60000)
        }
    }

    func finish(at duration: Double) async throws {
        guard input != nil else { writer.cancelWriting(); return }
        guard writer.status == .writing else { throw writer.error ?? EditingError.media("The media track is incomplete.") }
        // ScreenCaptureKit can stop sending frames while the screen is idle. Extend the
        // last image explicitly so the screen does not disappear while narration continues.
        let end = CMTime(seconds: duration, preferredTimescale: 60000)
        let finalTime = end - CMTime(value: 1, timescale: 60000)
        if let sample = lastVideoSample, finalTime > lastTime {
            let deadline = Date().addingTimeInterval(1)
            while input?.isReadyForMoreMediaData == false && Date() < deadline {
                try await Task.sleep(for: .milliseconds(2))
            }
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60000), presentationTimeStamp: finalTime, decodeTimeStamp: .invalid)
            var final: CMSampleBuffer?
            guard input?.isReadyForMoreMediaData == true,
                  CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample,
                    sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &final) == noErr,
                  let final, input?.append(final) == true else {
                throw writer.error ?? EditingError.media("Could not finalize the last video frame.")
            }
        }
        writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 60000))
        input?.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? EditingError.media("Could not finalize a media track.") }
    }
}
