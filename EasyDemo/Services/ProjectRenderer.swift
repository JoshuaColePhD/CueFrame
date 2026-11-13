import AVFoundation
import CoreImage

final class ProjectInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let screenID: CMPersistentTrackID
    let cameraID: CMPersistentTrackID?
    let project: RecordingProject
    let plan: EditPlan
    let ranges: [MediaRange]

    init(project: RecordingProject, plan: EditPlan, ranges: [MediaRange], duration: CMTime,
         screenID: CMPersistentTrackID, cameraID: CMPersistentTrackID?) {
        self.project = project; self.plan = plan; self.ranges = ranges
        self.screenID = screenID; self.cameraID = cameraID
        timeRange = CMTimeRange(start: .zero, duration: duration)
        requiredSourceTrackIDs = ([screenID] + (cameraID.map { [$0] } ?? [])).map { NSNumber(value: $0) }
    }
}

/// AVPlayer and AVAssetExportSession both use this compositor.
final class ProjectCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String: Any]? { [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA] }
    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferMetalCompatibilityKey as String: true]
    }
    private let queue = DispatchQueue(label: "com.joshuacole.easydemo.compositor", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let background = BackgroundRenderer()
    private let webcam = WebcamOverlayRenderer()
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { autoreleasepool {
            guard let instruction = request.videoCompositionInstruction as? ProjectInstruction,
                  let output = request.renderContext.newPixelBuffer() else {
                request.finish(with: EditingError.media("Could not allocate an export frame.")); return
            }
            let size = request.renderContext.size
            let canvas = CGRect(origin: .zero, size: size)
            var image = self.background.createBackground(size: size, style: instruction.project.background.style)
            let sourceTime = EditPlan.sourceTime(for: request.compositionTime.seconds, ranges: instruction.ranges)
            if let screen = request.sourceFrame(byTrackID: instruction.screenID) {
                var source = CIImage(cvPixelBuffer: screen)
                if let zoom = instruction.plan.zooms.first(where: { $0.amount(at: sourceTime) > 0 }) {
                    let scale = 1 + (zoom.scale - 1) * zoom.amount(at: sourceTime)
                    let extent = source.extent
                    let w = extent.width / scale, h = extent.height / scale
                    let x = min(max(extent.width * zoom.x - w / 2, 0), extent.width - w)
                    let y = min(max(extent.height * (1 - zoom.y) - h / 2, 0), extent.height - h)
                    source = source.cropped(to: CGRect(x: x, y: y, width: w, height: h))
                        .transformed(by: CGAffineTransform(translationX: -x, y: -y))
                }
                let inset = 32 * size.width / 1920
                let available = canvas.insetBy(dx: inset, dy: inset)
                let factor = min(available.width / source.extent.width, available.height / source.extent.height) * instruction.project.windowScale
                let dimensions = CGSize(width: source.extent.width * factor, height: source.extent.height * factor)
                let target = CGRect(x: (size.width - dimensions.width) / 2, y: (size.height - dimensions.height) / 2,
                                    width: dimensions.width, height: dimensions.height)
                source = source.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
                    .transformed(by: CGAffineTransform(translationX: target.minX, y: target.minY))
                // A rounded screen frame is independent from the squircle camera mask.
                let mask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: ["inputExtent": CIVector(cgRect: target),
                    "inputRadius": 12 * size.width / 1920, "inputColor": CIColor.white])?.outputImage
                if let mask { source = source.applyingFilter("CIBlendWithAlphaMask", parameters: ["inputMaskImage": mask]) }
                image = source.composited(over: image)
            }
            if let id = instruction.cameraID, let camera = request.sourceFrame(byTrackID: id) {
                image = self.webcam.createOverlay(webcamFrame: CIImage(cvPixelBuffer: camera), configuration: instruction.project.webcam,
                    canvasSize: size, scaleFactor: size.width / 1280).composited(over: image)
            }
            self.context.render(image.cropped(to: canvas), to: output)
            request.finish(withComposedVideoFrame: output)
        } }
    }

    func cancelAllPendingVideoCompositionRequests() { queue.sync {} }
}

struct RenderedProject {
    let asset: AVMutableComposition
    let video: AVMutableVideoComposition
    let audio: AVMutableAudioMix
    var playerItem: AVPlayerItem {
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = video; item.audioMix = audio
        return item
    }
}

enum ProjectRenderer {
    static func build(project: RecordingProject, plan: EditPlan) async throws -> RenderedProject {
        let validated = try plan.validated(duration: project.duration)
        guard project.width > 0, project.height > 0, project.width <= 7680, project.height <= 4320,
              (1...60).contains(project.frameRate) else { throw EditingError.invalidPlan }
        let ranges = validated.keptRanges(duration: project.duration)
        let composition = AVMutableComposition()
        let screenAsset = AVURLAsset(url: try project.mediaURL(project.screenFile))
        guard let screen = try await screenAsset.loadTracks(withMediaType: .video).first else { throw EditingError.noScreen }
        let screenTrack = try await add(track: screen, type: .video, ranges: ranges, to: composition)
        var cameraID: CMPersistentTrackID?
        if project.webcam.isEnabled, let file = project.cameraFile {
            let asset = AVURLAsset(url: try project.mediaURL(file))
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                cameraID = try await add(track: track, type: .video, ranges: ranges, to: composition).trackID
            } else { throw EditingError.media("The camera track is missing or incomplete. Its source file is preserved.") }
        }
        var audioParameters: [AVMutableAudioMixInputParameters] = []
        for (file, volume) in [(project.microphoneFile, project.microphoneVolume), (project.systemAudioFile, Float(1))] {
            guard let file else { continue }
            let url = try project.mediaURL(file)
            if file == project.systemAudioFile {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size == 0 { continue }
            }
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                // A system track may be empty if no app produced audio; narration must exist.
                if file == project.systemAudioFile { continue }
                throw EditingError.media("The microphone track is missing or incomplete.")
            }
            let destination = try await add(track: track, type: .audio, ranges: ranges, to: composition)
            let parameters = AVMutableAudioMixInputParameters(track: destination)
            parameters.setVolume(volume, at: .zero)
            var offset = 0.0
            for range in ranges {
                let fade = min(0.008, range.duration / 4)
                parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: volume,
                    timeRange: CMTimeRange(start: time(offset), duration: time(fade)))
                parameters.setVolumeRamp(fromStartVolume: volume, toEndVolume: 0,
                    timeRange: CMTimeRange(start: time(offset + range.duration - fade), duration: time(fade)))
                offset += range.duration
            }
            audioParameters.append(parameters)
        }
        let duration = time(ranges.reduce(0) { $0 + $1.duration })
        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = ProjectCompositor.self
        video.renderSize = CGSize(width: project.width, height: project.height)
        video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(project.frameRate))
        video.instructions = [ProjectInstruction(project: project, plan: validated, ranges: ranges, duration: duration,
            screenID: screenTrack.trackID, cameraID: cameraID)]
        let mix = AVMutableAudioMix(); mix.inputParameters = audioParameters
        return RenderedProject(asset: composition, video: video, audio: mix)
    }

    private static func add(track: AVAssetTrack, type: AVMediaType, ranges: [MediaRange], to composition: AVMutableComposition) async throws -> AVMutableCompositionTrack {
        guard let destination = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw EditingError.media("Could not create the editing timeline.") }
        let available = try await track.load(.timeRange)
        var offset = 0.0
        for range in ranges {
            let requested = CMTimeRange(start: time(range.start), end: time(range.end))
            let intersection = CMTimeRangeGetIntersection(requested, otherRange: available)
            if intersection.isValid, intersection.duration > .zero {
                try destination.insertTimeRange(intersection, of: track, at: time(offset) + intersection.start - requested.start)
            }
            offset += range.duration
        }
        let total = time(offset)
        if destination.timeRange.end < total { destination.insertEmptyTimeRange(CMTimeRange(start: destination.timeRange.end, end: total)) }
        return destination
    }

    static func export(project: RecordingProject, plan: EditPlan, to destination: URL,
                       progress: @escaping @Sendable (Float) -> Void = { _ in }) async throws {
        let originals = try [project.screenFile, project.cameraFile, project.microphoneFile, project.systemAudioFile, "project.json"]
            .compactMap { $0 }.map { try project.mediaURL($0).resolvingSymlinksInPath().standardizedFileURL }
        let output = destination.resolvingSymlinksInPath().standardizedFileURL
        guard !originals.contains(output), output != project.background.imageURL?.resolvingSymlinksInPath().standardizedFileURL else {
            throw EditingError.media("Choose a different export filename. That file is part of the recording's original project.")
        }
        let rendered = try await build(project: project, plan: plan)
        let preset: String
        switch project.codec {
        case .h264: preset = AVAssetExportPresetHighestQuality
        case .hevc: preset = AVAssetExportPresetHEVCHighestQuality
        case .prores: preset = AVAssetExportPresetAppleProRes422LPCM
        }
        guard let exporter = AVAssetExportSession(asset: rendered.asset, presetName: preset) else { throw EditingError.media("This export codec is unavailable on this Mac.") }
        // A save-panel grant covers the chosen file, not arbitrary siblings. Foundation
        // supplies a writable replacement directory on the destination's volume.
        let replacement = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                     appropriateFor: destination, create: true)
        let temporary = replacement.appendingPathComponent("export.\(project.codec == .h264 ? "mp4" : "mov")")
        defer { try? FileManager.default.removeItem(at: replacement) }
        exporter.videoComposition = rendered.video; exporter.audioMix = rendered.audio
        exporter.outputURL = temporary; exporter.outputFileType = project.codec == .h264 ? .mp4 : .mov
        exporter.timeRange = rendered.video.instructions[0].timeRange
        exporter.shouldOptimizeForNetworkUse = true
        let monitor = Task {
            while !Task.isCancelled {
                progress(exporter.progress)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { monitor.cancel() }
        try await withTaskCancellationHandler {
            await exporter.export()
            try Task.checkCancellation()
            guard exporter.status == .completed else { throw exporter.error ?? EditingError.media("The export did not complete.") }
        } onCancel: { exporter.cancelExport() }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
        progress(1)
    }

    static func time(_ value: Double) -> CMTime { CMTime(seconds: value, preferredTimescale: 60000) }
}
