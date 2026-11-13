import AppKit
@preconcurrency import AVFoundation
import ScreenCaptureKit

enum AudioLevels {
    static func decibels(_ sample: CMSampleBuffer) -> Double? {
        guard let description = sample.formatDescription,
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mFormatID == kAudioFormatLinearPCM else { return nil }
        let capacity = max(1, Int(format.mChannelsPerFrame))
        let storage = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<AudioBufferList>.size + (capacity - 1) * MemoryLayout<AudioBuffer>.size, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        let pointer = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        pointer.pointee.mNumberBuffers = UInt32(capacity)
        let list = UnsafeMutableAudioBufferListPointer(pointer)
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: nil,
            bufferListOut: list.unsafeMutablePointer,
            bufferListSize: MemoryLayout<AudioBufferList>.size + (capacity - 1) * MemoryLayout<AudioBuffer>.size,
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &block) == noErr else { return nil }
        var sum = 0.0, count = 0
        for buffer in list {
            guard let data = buffer.mData else { continue }
            if format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32 {
                let values = data.bindMemory(to: Float.self, capacity: Int(buffer.mDataByteSize) / 4)
                for i in 0..<(Int(buffer.mDataByteSize) / 4) { let v = Double(values[i]); sum += v * v; count += 1 }
            } else if format.mBitsPerChannel == 16 {
                let values = data.bindMemory(to: Int16.self, capacity: Int(buffer.mDataByteSize) / 2)
                for i in 0..<(Int(buffer.mDataByteSize) / 2) { let v = Double(values[i]) / 32768; sum += v * v; count += 1 }
            }
        }
        guard count > 0 else { return nil }
        return max(-100, 10 * log10(max(1e-10, sum / Double(count))))
    }
}

/// Media and metadata are confined to the serial sample queue.
final class CaptureSession: NSObject, SCStreamOutput, SCStreamDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.joshuacole.easydemo.capture", qos: .userInitiated)
    private var stream: SCStream?
    private var camera: AVCaptureSession?
    private var cameraObserver: NSObjectProtocol?
    private var writers: [String: MediaTrackWriter] = [:]
    private var origin = CMTime.invalid
    private var accepting = false
    private var failure: String?
    private var activity: [ActivitySample] = []
    private var micDB: Double?
    private var systemDB: Double?
    private var micTime = -1.0
    private var systemTime = -1.0
    private var cameraTime = -1.0
    private var screenChanged = false
    private var lastActivity = -1.0
    private var lastSignature: [UInt8]?
    private let configuration: RecordingConfiguration
    private let folder: URL
    private var captureSize = CGSize.zero
    var dimensions: CGSize { queue.sync { captureSize } }
    var onFailure: (@Sendable (String) -> Void)?

    init(configuration: RecordingConfiguration, folder: URL) { self.configuration = configuration; self.folder = folder }

    func start() async throws {
        let filter: SCContentFilter
        if let authorized = configuration.authorizedFilter {
            filter = authorized
        } else {
        let content = try await SCShareableContent.current
        switch configuration.source {
        case .window(let info):
            guard let window = content.windows.first(where: { $0.windowID == info.id }) else { throw EditingError.media("The selected window is no longer available.") }
            filter = SCContentFilter(desktopIndependentWindow: window)
        case .display(let info):
            guard let display = content.displays.first(where: { $0.displayID == info.id }) else { throw EditingError.media("The selected display is no longer available.") }
            filter = SCContentFilter(display: display, excludingApplications: content.applications.filter {
                $0.bundleIdentifier == Bundle.main.bundleIdentifier
            }, exceptingWindows: [])
        }
        }
        let settings = SCStreamConfiguration()
        let ratio = min(1, 3840 / max(filter.contentRect.width * CGFloat(filter.pointPixelScale), filter.contentRect.height * CGFloat(filter.pointPixelScale)))
        settings.width = max(2, Int(filter.contentRect.width * CGFloat(filter.pointPixelScale) * ratio) / 2 * 2)
        settings.height = max(2, Int(filter.contentRect.height * CGFloat(filter.pointPixelScale) * ratio) / 2 * 2)
        settings.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(configuration.frameRate))
        settings.pixelFormat = kCVPixelFormatType_32BGRA; settings.showsCursor = true; settings.queueDepth = 5
        settings.capturesAudio = configuration.audio.systemAudioEnabled
        settings.excludesCurrentProcessAudio = true
        settings.sampleRate = 48_000; settings.channelCount = 2
        settings.captureMicrophone = configuration.audio.microphoneEnabled
        if let deviceID = configuration.audio.selectedMicrophoneDeviceID {
            guard AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices.contains(where: { $0.uniqueID == deviceID }) else {
                throw EditingError.media("The selected microphone is disconnected. Choose another input.")
            }
            settings.microphoneCaptureDeviceID = deviceID
        }
        writers["screen"] = try MediaTrackWriter(url: folder.appendingPathComponent("screen.mov"))
        if configuration.audio.microphoneEnabled { writers["microphone"] = try MediaTrackWriter(url: folder.appendingPathComponent("microphone.mov")) }
        if configuration.audio.systemAudioEnabled { writers["system"] = try MediaTrackWriter(url: folder.appendingPathComponent("system.mov")) }
        if configuration.webcam.isEnabled {
            writers["camera"] = try MediaTrackWriter(url: folder.appendingPathComponent("camera.mov"))
            try await startCamera()
        }
        let stream = SCStream(filter: filter, configuration: settings, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if settings.capturesAudio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        if settings.captureMicrophone { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
        self.stream = stream
        queue.sync {
            captureSize = CGSize(width: settings.width, height: settings.height)
            origin = CMClockGetTime(CMClockGetHostTimeClock()); accepting = true
        }
        try await stream.startCapture()
    }

    private func startCamera() async throws {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices
        let device = configuration.webcam.selectedDeviceId.flatMap { id in devices.first { $0.uniqueID == id } } ??
            (configuration.webcam.selectedDeviceId == nil ? (AVCaptureDevice.default(for: .video) ?? devices.first) : nil)
        guard let device else { throw EditingError.media("The selected camera is unavailable. Choose another camera or turn off the overlay.") }
        let camera = AVCaptureSession()
        camera.beginConfiguration()
        if camera.canSetSessionPreset(.hd1280x720) { camera.sessionPreset = .hd1280x720 }
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        guard camera.canAddInput(input), camera.canAddOutput(output) else { camera.commitConfiguration(); throw EditingError.media("Could not configure the camera.") }
        camera.addInput(input); camera.addOutput(output); output.setSampleBufferDelegate(self, queue: queue)
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = true
        }
        camera.commitConfiguration(); self.camera = camera
        cameraObserver = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: camera, queue: nil) { [weak self] note in
            let message = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "The camera stopped unexpectedly."
            self?.queue.async { self?.fail(message) }
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { camera.startRunning(); continuation.resume() }
        }
        guard camera.isRunning else { throw EditingError.media("The camera could not start.") }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard accepting else { return }
        let time = (CMSampleBufferGetPresentationTimeStamp(sample) - origin).seconds
        guard time.isFinite, time >= 0 else { return }
        do {
            switch type {
            case .screen:
                guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                      let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue else { return }
                try writers["screen"]?.append(sample, origin: origin, video: true)
                if let image = sample.imageBuffer { screenChanged = screenChanged || hasScreenChanged(image) }
            case .audio:
                try writers["system"]?.append(sample, origin: origin, video: false)
                if let db = AudioLevels.decibels(sample) { systemDB = max(systemDB ?? -100, db) }; systemTime = time
            case .microphone:
                try writers["microphone"]?.append(sample, origin: origin, video: false)
                if let db = AudioLevels.decibels(sample) { micDB = max(micDB ?? -100, db) }; micTime = time
            @unknown default: break
            }
            if time - lastActivity >= 0.25 {
                activity.append(ActivitySample(time: time, microphoneDB: time - micTime < 0.4 ? micDB : nil,
                    systemDB: time - systemTime < 0.4 ? systemDB : nil, screenChanged: screenChanged))
                lastActivity = time; screenChanged = false; micDB = nil; systemDB = nil
            }
        } catch { fail(error.localizedDescription) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard accepting else { return }
        do {
            try writers["camera"]?.append(sample, origin: origin, video: true)
            cameraTime = (CMSampleBufferGetPresentationTimeStamp(sample) - origin).seconds
        }
        catch { fail(error.localizedDescription) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { queue.async { self.fail(error.localizedDescription) } }
    private func fail(_ message: String) {
        guard failure == nil else { return }
        failure = message; accepting = false; onFailure?(message)
    }

    private func hasScreenChanged(_ buffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return true }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
        var signature: [UInt8] = []
        for y in 0..<36 { for x in 0..<64 {
            let pixel = base.advanced(by: ((height - 1) * y / 35) * row + ((width - 1) * x / 63) * 4).assumingMemoryBound(to: UInt8.self)
            signature.append(UInt8((Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / 3))
        } }
        defer { lastSignature = signature }
        guard let old = lastSignature else { return true }
        return zip(old, signature).filter { abs(Int($0.0) - Int($0.1)) > 8 }.count >= 2
    }

    func elapsed() -> Double {
        queue.sync {
            let elapsed = origin.isValid ? max(0, (CMClockGetTime(CMClockGetHostTimeClock()) - origin).seconds) : 0
            if accepting, elapsed > 5 {
                if configuration.audio.microphoneEnabled, elapsed - micTime > 1.5 { fail("The microphone stopped sending audio. Check its connection and permission before recording again.") }
                if configuration.webcam.isEnabled, elapsed - cameraTime > 1.5 { fail("The camera stopped sending frames. Check its connection before recording again.") }
            }
            return elapsed
        }
    }

    func stop() async -> (Double, [ActivitySample], String?) {
        let duration = elapsed()
        queue.sync { accepting = false }
        if let observer = cameraObserver { NotificationCenter.default.removeObserver(observer); cameraObserver = nil }
        if let camera {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { camera.stopRunning(); continuation.resume() }
            }
        }
        if let stream { do { try await stream.stopCapture() } catch { queue.sync { if failure == nil { failure = error.localizedDescription } } } }
        self.stream = nil; camera = nil
        var finishFailure: String?
        for (name, writer) in writers {
            do { try await writer.finish(at: max(0.01, duration)) }
            catch { if finishFailure == nil { finishFailure = "\(name): \(error.localizedDescription)" } }
        }
        for name in ["screen", "microphone", "camera"] {
            if let writer = writers[name], writer.sampleCount == 0, finishFailure == nil { finishFailure = "No \(name) samples arrived. Check its permission and device before recording again." }
        }
        return queue.sync { (duration, activity, failure ?? finishFailure) }
    }
}
