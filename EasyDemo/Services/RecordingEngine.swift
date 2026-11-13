import AppKit
import AVFoundation
import Combine

@MainActor
final class RecordingEngine: ObservableObject {
    static let shared = RecordingEngine()
    enum Phase: String { case idle, starting, recording, stopping }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration = 0.0
    @Published var error: Error?
    @Published var lastRecordingResult: RecordingResult?
    @Published private(set) var startupStatus = "Starting capture…"
    private var preparationID: UUID?
    var canCancelStartup: Bool { phase == .starting && capture == nil }
    private var capture: CaptureSession?
    private var project: RecordingProject?
    private var timer: Timer?
    private var cursor: [CursorSample] = []
    private var monitor: Any?
    private var localMonitor: Any?
    private var source: CaptureSource?
    private var lastCursor: CGPoint?
    private let screenAllowed: () -> Bool
    private let requestAccess: (AVMediaType) async -> Bool

    init(screenAllowed: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
         requestAccess: @escaping (AVMediaType) async -> Bool = { await AVCaptureDevice.requestAccess(for: $0) }) {
        self.screenAllowed = screenAllowed; self.requestAccess = requestAccess
    }

    func startRecording(configuration: RecordingConfiguration, outputDirectoryManager: OutputDirectoryManager? = nil) async throws {
        guard phase == .idle else { return }
        let attempt = UUID(); preparationID = attempt
        phase = .starting; isRecording = true; error = nil; recordingDuration = 0; cursor = []; lastCursor = nil
        do {
            guard configuration.authorizedFilter != nil || screenAllowed() else {
                throw EditingError.media("Choose a window or display in the macOS sharing picker before recording.")
            }
            if configuration.audio.microphoneEnabled {
                startupStatus = "Waiting for macOS microphone permission…"
                let granted = await requestAccess(.audio)
                guard preparationID == attempt else { throw CancellationError() }
                guard granted else { throw EditingError.media("Microphone access is denied. Grant access or turn off the microphone before recording.") }
            }
            if configuration.webcam.isEnabled {
                startupStatus = "Waiting for macOS camera permission…"
                let granted = await requestAccess(.video)
                guard preparationID == attempt else { throw CancellationError() }
                guard granted else { throw EditingError.media("Camera access is denied. Grant access or turn off the overlay before recording.") }
            }
            WebcamCapture.stopAllCaptures()
            let folder = RecordingProject.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let dimensions = configuration.resolution.dimensions ?? CGSize(width: 1920, height: 1080)
            var background = SavedBackground(configuration.background)
            if case .image(let url) = configuration.background {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let local = folder.appendingPathComponent("background.\(url.pathExtension.isEmpty ? "jpg" : url.pathExtension)")
                try FileManager.default.copyItem(at: url, to: local)
                background = SavedBackground(.image(local))
            }
            var value = RecordingProject(title: configuration.source.displayName,
                webcam: configuration.webcam, microphoneVolume: configuration.audio.microphoneVolume,
                background: background, windowScale: configuration.windowScale,
                width: Int(dimensions.width), height: Int(dimensions.height), frameRate: configuration.frameRate, codec: configuration.codec)
            value.folder = folder
            value.cameraFile = configuration.webcam.isEnabled ? "camera.mov" : nil
            value.microphoneFile = configuration.audio.microphoneEnabled ? "microphone.mov" : nil
            value.systemAudioFile = configuration.audio.systemAudioEnabled ? "system.mov" : nil
            project = value; try value.save()
            let session = CaptureSession(configuration: configuration, folder: folder)
            session.onFailure = { [weak self] message in
                Task { @MainActor in
                    guard let self else { return }
                    self.error = EditingError.media(message)
                    if self.phase == .recording { _ = await self.stopRecording() }
                }
            }
            capture = session; source = configuration.source
            startupStatus = "Starting capture…"
            try await session.start()
            if configuration.resolution == .original {
                value.width = Int(session.dimensions.width); value.height = Int(session.dimensions.height)
                project = value; try value.save()
            }
            phase = .recording
            let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .mouseMoved, .leftMouseDragged, .scrollWheel]
            monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.observeCursor(event) }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in self?.observeCursor(event); return event }
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.recordingDuration = self?.capture?.elapsed() ?? 0 }
            }
            StatusBarManager.shared.show()
        } catch {
            guard preparationID == attempt else { throw CancellationError() }
            if let capture { _ = await capture.stop() }
            project?.state = "failed"; project?.failure = error.localizedDescription; try? project?.save()
            cleanup(); self.error = error; throw error
        }
    }

    private func observeCursor(_ event: NSEvent) {
        guard let source, let capture, phase == .recording else { return }
        let mouse = NSEvent.mouseLocation
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: mouse.x, y: mainHeight - mouse.y)
        let bounds: CGRect
        switch source {
        case .display(let info): bounds = CGDisplayBounds(info.id)
        case .window(let info):
            guard let data = CGWindowListCopyWindowInfo(.optionIncludingWindow, info.id) as? [[String: Any]],
                  let dictionary = data.first?[kCGWindowBounds as String] as? [String: Any],
                  let current = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return }
            bounds = current
        }
        guard bounds.contains(point), bounds.width > 0, bounds.height > 0 else { return }
        let clicked = event.type == .leftMouseDown || event.type == .rightMouseDown
        if let lastCursor, !clicked, hypot(lastCursor.x - point.x, lastCursor.y - point.y) < 3 { return }
        let now = capture.elapsed()
        if !clicked, let last = cursor.last, now - last.time < 0.1 { return }
        cursor.append(CursorSample(time: now, x: (point.x - bounds.minX) / bounds.width,
                                   y: (point.y - bounds.minY) / bounds.height, clicked: clicked))
        lastCursor = point
    }

    func stopRecording() async -> RecordingResult? {
        guard phase == .recording, let capture, var value = project else { return nil }
        phase = .stopping; timer?.invalidate(); timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        let (duration, activity, failure) = await capture.stop()
        value.duration = duration; value.activity = activity; value.cursor = cursor
        value.failure = failure; value.state = failure == nil ? "complete" : "interrupted"
        do { try value.save() } catch { self.error = error }
        if let failure { error = EditingError.media(failure) }
        let screen = value.folder.appendingPathComponent(value.screenFile)
        let size = (try? screen.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let result = RecordingResult(fileURL: screen, duration: duration, fileSize: Int64(size),
                                     timestamp: value.created, projectFolder: value.folder)
        lastRecordingResult = result
        cleanup()
        return result
    }

    private func cleanup() {
        timer?.invalidate(); timer = nil; capture = nil; project = nil; source = nil
        phase = .idle; isRecording = false; StatusBarManager.shared.hide()
        preparationID = nil
    }

    func cancelStartup() {
        guard canCancelStartup else { return }
        preparationID = nil
        cleanup()
    }
}
