import Testing
import SwiftUI
import AVFoundation
import CoreImage
@testable import EasyDemo

struct MediaIntegrationTests {
    @Test func exportKeepsCameraFixedAndCutsEveryTrackTogether() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await video(url: folder.appendingPathComponent("screen.mov"), duration: 8, camera: false)
        try await video(url: folder.appendingPathComponent("camera.mov"), duration: 8, camera: true)
        try audio(url: folder.appendingPathComponent("voice.caf"), duration: 8)
        var project = fixtureProject(folder: folder, duration: 8)
        project.cameraFile = "camera.mov"; project.microphoneFile = "voice.caf"
        project.systemAudioFile = "system.mov"
        try Data().write(to: folder.appendingPathComponent("system.mov"))
        let plan = EditPlan(zooms: [ZoomSuggestion(start: 1, end: 4, x: 0.2, y: 0.5, scale: 2, reason: "Test focus")],
                            pauses: [PauseSuggestion(start: 4, end: 6)])
        let rendered = try await ProjectRenderer.build(project: project, plan: plan)
        let tracks = try await rendered.asset.load(.tracks)
        #expect(tracks.count == 3)
        for track in tracks {
            let range = try await track.load(.timeRange)
            #expect(abs(range.duration.seconds - 6) < 0.05)
        }
        let output = folder.appendingPathComponent("edited.mp4")
        try await ProjectRenderer.export(project: project, plan: plan, to: output)
        // Replacing a previously selected output must also preserve the complete media.
        try await ProjectRenderer.export(project: project, plan: plan, to: output)
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 6) < 0.11)
        let generator = AVAssetImageGenerator(asset: asset)
        // The default infinite tolerance can return the same keyframe for both requests.
        // Compare the intended moments, independently of the encoder's GOP layout.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let beforeFrame = try await generator.image(at: ProjectRenderer.time(0.8))
        let afterFrame = try await generator.image(at: ProjectRenderer.time(2.5))
        #expect(abs(beforeFrame.actualTime.seconds - 0.8) < 1.0 / 30)
        #expect(abs(afterFrame.actualTime.seconds - 2.5) < 1.0 / 30)
        let unzoomed = beforeFrame.image, zoomed = afterFrame.image
        let first = colorBounds(unzoomed), second = colorBounds(zoomed)
        #expect(first != nil)
        let before = try #require(first), after = try #require(second)
        // H.264 chroma reconstruction can shift a thresholded edge by one pixel.
        #expect(zip(before, after).allSatisfy { abs($0 - $1) <= 1 })
        let redBefore = try #require(colorBounds(unzoomed, green: false))
        let redAfter = try #require(colorBounds(zoomed, green: false))
        #expect(redAfter[1] - redAfter[0] > (redBefore[1] - redBefore[0]) * 3 / 2)
        #expect(try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("screen.mov").path)[.size] as? Int ?? 0 > 0)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("voice.caf").path))
    }

    @Test func tenMinuteSyntheticTimelineRetainsTimingAtBothEnds() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await video(url: folder.appendingPathComponent("screen.mov"), duration: 600, camera: false, fps: 1)
        try audio(url: folder.appendingPathComponent("voice.caf"), duration: 600)
        var project = fixtureProject(folder: folder, duration: 600)
        project.webcam.isEnabled = false; project.microphoneFile = "voice.caf"
        let rendered = try await ProjectRenderer.build(project: project, plan: EditPlan())
        let tracks = try await rendered.asset.load(.tracks)
        let video = try #require(tracks.first { $0.mediaType == .video })
        let audio = try #require(tracks.first { $0.mediaType == .audio })
        let videoRange = try await video.load(.timeRange), audioRange = try await audio.load(.timeRange)
        #expect(abs(videoRange.start.seconds - audioRange.start.seconds) < 0.1)
        #expect(abs(videoRange.end.seconds - audioRange.end.seconds) < 0.1)
        #expect(abs(videoRange.end.seconds - 600) < 0.1)
    }

    private func video(url: URL, duration: Int, camera: Bool, fps: Int = 10) async throws {
        let writer = try AVAssetWriter(url: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        #expect(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        let context = CIContext()
        let base = CIImage(color: camera ? CIColor(red: 0, green: 1, blue: 0) : CIColor(red: 0, green: 0, blue: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 320, height: 180))
        let image = camera ? base : CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 10, y: 30, width: 60, height: 120)).composited(over: base)
        for index in 0..<(duration * fps) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, try #require(adaptor.pixelBufferPool), &buffer)
            let pixel = try #require(buffer)
            context.render(image, to: pixel)
            #expect(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: Int32(fps))))
        }
        writer.endSession(atSourceTime: CMTime(seconds: Double(duration), preferredTimescale: 600))
        input.markAsFinished(); await writer.finishWriting()
        #expect(writer.status == .completed)
    }

    private func audio(url: URL, duration: Int) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        let channel = try #require(buffer.floatChannelData?[0])
        for frame in 0..<48_000 { channel[frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 48_000) * 0.1) }
        for _ in 0..<duration { try file.write(from: buffer) }
    }

    private func colorBounds(_ image: CGImage, green: Bool = true) -> [Int]? {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4
            let matches = green ? (data[i] < 55 && data[i + 1] > 170 && data[i + 2] < 55) : (data[i] > 170 && data[i + 1] < 55 && data[i + 2] < 55)
            if matches { xs.append(x); ys.append(y) }
        } }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        return [minX, maxX, minY, maxY]
    }
}
