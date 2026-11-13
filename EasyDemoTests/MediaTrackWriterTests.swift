import Testing
import AVFoundation
import CoreImage
@testable import EasyDemo

struct MediaTrackWriterTests {
    @Test func hostClockTimestampsRemainAlignedAcrossTenMinutes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let origin = CMTime(seconds: 10000, preferredTimescale: 48000)
        let videoURL = folder.appendingPathComponent("screen.mov"), audioURL = folder.appendingPathComponent("microphone.mov")
        let video = try MediaTrackWriter(url: videoURL), audio = try MediaTrackWriter(url: audioURL)
        let frame = try videoSample(at: origin + ProjectRenderer.time(0.1))
        for _ in 0..<100 {
            try video.append(frame, origin: origin, video: true)
            if video.sampleCount > 0 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        // Audio is continuous, like a real microphone; the screen stays idle after its first frame.
        let template = try audioSample(at: origin + ProjectRenderer.time(0.1))
        for offset in stride(from: 0.1, to: 600, by: 1) {
            // This fixture produces ten minutes of audio faster than a live input.
            // Do not interpret offline encoder pressure as a hardware capture failure.
            let deadline = Date().addingTimeInterval(10)
            while !audio.isReadyForMoreMediaData {
                try #require(Date() < deadline, "The synthetic audio encoder did not become ready.")
                try await Task.sleep(for: .milliseconds(2))
            }
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000),
                presentationTimeStamp: origin + ProjectRenderer.time(offset), decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: template,
                sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &sample)
            try audio.append(try #require(sample), origin: origin, video: false)
        }
        try await video.finish(at: 600); try await audio.finish(at: 600)
        #expect(video.sampleCount == 1 && audio.sampleCount == 600)
        let vAsset = AVURLAsset(url: videoURL), aAsset = AVURLAsset(url: audioURL)
        let v = try #require(try await vAsset.loadTracks(withMediaType: .video).first)
        let a = try #require(try await aAsset.loadTracks(withMediaType: .audio).first)
        let vr = try await v.load(.timeRange), ar = try await a.load(.timeRange)
        #expect(abs(vr.start.seconds - ar.start.seconds) < 0.1)
        #expect(abs(vr.end.seconds - ar.end.seconds) < 0.1)
        #expect(vr.end.seconds > 599.8 && vr.end.seconds <= 600.1)
    }

    private func videoSample(at time: CMTime) throws -> CMSampleBuffer {
        var pixel: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel)
        let image = try #require(pixel)
        CIContext().render(CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 180)), to: image)
        var description: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image, formatDescriptionOut: &description)
        var timing = CMSampleTimingInfo(duration: ProjectRenderer.time(0.1), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image, formatDescription: try #require(description), sampleTiming: &timing, sampleBufferOut: &sample)
        return try #require(sample)
    }

    private func audioSample(at time: CMTime) throws -> CMSampleBuffer {
        var format = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 2,
            mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var description: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &format, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
        let values = (0..<48000).map { Int16(sin(Double($0) * 2 * .pi * 440 / 48000) * 3000) }
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: 96000,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: 96000, flags: 0, blockBufferOut: &block)
        let data = try #require(block)
        values.withUnsafeBytes { bytes in _ = CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: data, offsetIntoDestination: 0, dataLength: bytes.count) }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?, size = 2
        CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: data, formatDescription: description,
            sampleCount: 48000, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        let result = try #require(sample)
        #expect((AudioLevels.decibels(result) ?? -100) > -30)
        return result
    }
}
