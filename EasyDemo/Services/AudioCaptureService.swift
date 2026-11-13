@preconcurrency import AVFoundation
import Combine

/// Preflight microphone meter. Recording itself uses ScreenCaptureKit's synchronized inputs.
@MainActor
final class AudioCaptureService: NSObject, ObservableObject {
    @Published var isCapturing = false
    @Published var hasPermission = false
    @Published var level = 0.0
    @Published var error: String?
    private var session: AVCaptureSession?
    private let delegate = MeterDelegate()
    private var generation = UUID()

    func getAvailableMicrophones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    }
    @discardableResult func checkMicrophonePermission() -> Bool {
        hasPermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        return hasPermission
    }
    func requestMicrophonePermission() async -> Bool {
        hasPermission = await AVCaptureDevice.requestAccess(for: .audio)
        return hasPermission
    }
    func startMeter(deviceID: String?) async {
        stopCapture(); error = nil
        guard checkMicrophonePermission() else { return }
        let token = UUID(); generation = token
        do {
            let devices = getAvailableMicrophones()
            let device = deviceID.flatMap { id in devices.first { $0.uniqueID == id } } ?? (deviceID == nil ? AVCaptureDevice.default(for: .audio) : nil)
            guard let device else { throw EditingError.media("The selected microphone is unavailable.") }
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureAudioDataOutput()
            let value = AVCaptureSession()
            guard value.canAddInput(input), value.canAddOutput(output) else { throw EditingError.media("Could not start the microphone meter.") }
            value.addInput(input); value.addOutput(output)
            delegate.onLevel = { [weak self] db in
                Task { @MainActor [weak self] in
                    guard self?.generation == token else { return }
                    self?.level = max(0, min(1, (db + 60) / 60))
                }
            }
            output.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "com.joshuacole.easydemo.meter"))
            session = value
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async { value.startRunning(); continuation.resume() }
            }
            guard generation == token else { value.stopRunning(); return }
            isCapturing = value.isRunning
            if !isCapturing { error = "The microphone meter could not start." }
        } catch { self.error = error.localizedDescription }
    }
    func stopCapture() {
        generation = UUID(); level = 0; isCapturing = false
        let value = session; session = nil
        DispatchQueue.global(qos: .utility).async { value?.stopRunning() }
    }
}

private final class MeterDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var onLevel: (@Sendable (Double) -> Void)?
    private var lastUpdate = 0.0
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time - lastUpdate > 0.08, let level = AudioLevels.decibels(sampleBuffer) else { return }
        lastUpdate = time; onLevel?(level)
    }
}
