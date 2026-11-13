import Testing
import SwiftUI
import AVFoundation
@testable import EasyDemo

struct RecordingStartupTests {
    @Test @MainActor func cancellationWhileWaitingDoesNotStartALateRecording() async throws {
        let gate = PermissionGate()
        let engine = RecordingEngine(screenAllowed: { true }, requestAccess: { _ in await gate.request() })
        let start = Task { try await engine.startRecording(configuration: configuration()) }
        await gate.waitUntilRequested()
        #expect(engine.phase == .starting && engine.canCancelStartup)
        engine.cancelStartup()
        #expect(engine.phase == .idle && !engine.isRecording)
        await gate.resolve(true)
        do { try await start.value; Issue.record("Expected the cancelled startup to finish without recording") }
        catch { #expect(error is CancellationError) }
        #expect(engine.phase == .idle && engine.error == nil && engine.lastRecordingResult == nil)
    }

    @Test @MainActor func screenDenialLeavesTheRecorderIdleWithoutRequestingDevices() async {
        var deviceRequests = 0
        let engine = RecordingEngine(screenAllowed: { false }, requestAccess: { _ in deviceRequests += 1; return true })
        do { try await engine.startRecording(configuration: configuration()); Issue.record("Expected permission denial") }
        catch { #expect(engine.error != nil) }
        #expect(deviceRequests == 0 && engine.phase == .idle && !engine.isRecording)
    }

    private func configuration() -> RecordingConfiguration {
        RecordingConfiguration(source: .display(DisplayInfo(id: .max, width: 1920, height: 1080, scDisplay: nil)),
            background: .solidColor(.black), webcam: .default, audio: .default, resolution: .hd1080, frameRate: 30,
            codec: .h264, outputURL: URL(fileURLWithPath: "/unused.mov"), windowScale: 0.9)
    }
}

private actor PermissionGate {
    private var response: CheckedContinuation<Bool, Never>?
    private var requested: CheckedContinuation<Void, Never>?
    func request() async -> Bool {
        await withCheckedContinuation { continuation in
            response = continuation; requested?.resume(); requested = nil
        }
    }
    func waitUntilRequested() async {
        if response != nil { return }
        await withCheckedContinuation { requested = $0 }
    }
    func resolve(_ allowed: Bool) { response?.resume(returning: allowed); response = nil }
}
