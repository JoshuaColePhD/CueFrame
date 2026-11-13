//
//  EasyDemoTests.swift
//  EasyDemoTests
//
//  Created by Daniel Oquelis on 28.10.25.
//

import Testing
import SwiftUI
import AVFoundation
import CoreImage
@testable import EasyDemo

struct EasyDemoTests {

    @Test func cutsMergeAndMapAllTracksToTheSameSourceTime() throws {
        let plan = EditPlan(pauses: [PauseSuggestion(start: 2, end: 4), PauseSuggestion(start: 3, end: 6)])
        _ = try plan.validated(duration: 10)
        #expect(plan.keptRanges(duration: 10) == [MediaRange(start: 0, end: 2), MediaRange(start: 6, end: 10)])
        #expect(EditPlan.sourceTime(for: 2, ranges: plan.keptRanges(duration: 10)) == 6)
        #expect(EditPlan.sourceTime(for: 5, ranges: plan.keptRanges(duration: 10)) == 9)
    }

    @Test func unsafeAndOverlappingEditsAreRejected() {
        let invalid = ZoomSuggestion(start: 1, end: 3, x: 1.1, y: 0.5, scale: 2, reason: "invalid")
        #expect(throws: (any Error).self) { try EditPlan(zooms: [invalid]).validated(duration: 10) }
        let a = ZoomSuggestion(start: 1, end: 3, x: 0.5, y: 0.5, scale: 2, reason: "first")
        let b = ZoomSuggestion(start: 2, end: 4, x: 0.5, y: 0.5, scale: 2, reason: "second")
        #expect(throws: (any Error).self) { try EditPlan(zooms: [a, b]).validated(duration: 10) }
        #expect(throws: (any Error).self) { try EditPlan(pauses: [PauseSuggestion(start: 0, end: 10)]).validated(duration: 10) }
        #expect(a.amount(at: 1) == 0)
        #expect(a.amount(at: 2) == 1)
        #expect(a.amount(at: 3) == 0)
    }

    @Test func silenceTrimsRequireObservedSilenceAndNoActivity() {
        let samples = stride(from: 0.0, through: 6, by: 0.25).map {
            ActivitySample(time: $0, microphoneDB: -65, systemDB: -70, screenChanged: false)
        }
        let cuts = PauseDetector.suggestions(samples: samples, cursor: [], duration: 6, microphone: true, system: true)
        #expect(cuts.count == 1)
        #expect(cuts[0].start == 0.3)
        #expect(cuts[0].end == 5.7)
        #expect(PauseDetector.suggestions(samples: samples, cursor: [], duration: 6, microphone: false, system: true).isEmpty)
        let missing = samples.map { ActivitySample(time: $0.time, microphoneDB: nil, systemDB: nil, screenChanged: false) }
        #expect(PauseDetector.suggestions(samples: missing, cursor: [], duration: 6, microphone: true, system: true).isEmpty)
        let active = samples.map { ActivitySample(time: $0.time, microphoneDB: -60, systemDB: -10, screenChanged: false) }
        #expect(PauseDetector.suggestions(samples: active, cursor: [], duration: 6, microphone: true, system: true).isEmpty)
        let moving = samples.map { ActivitySample(time: $0.time, microphoneDB: -60, systemDB: -70, screenChanged: true) }
        #expect(PauseDetector.suggestions(samples: moving, cursor: [], duration: 6, microphone: true, system: true).isEmpty)
    }

    @Test func missingObservationGapsAreNotCut() {
        let samples = [0.0, 0.25, 0.5, 4.0, 4.25, 4.5].map {
            ActivitySample(time: $0, microphoneDB: -60, systemDB: nil, screenChanged: false)
        }
        #expect(PauseDetector.suggestions(samples: samples, cursor: [], duration: 6, microphone: true, system: false).isEmpty)
    }

    @Test func preferencesSurviveRelaunch() throws {
        let name = "EasyDemoTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var value = RecorderPreferences()
        #expect(value.webcam.isEnabled && value.audio.microphoneEnabled)
        #expect(value.webcam.shape == .squircle)
        value.webcam.selectedDeviceId = "test-camera"
        value.audio.selectedMicrophoneDeviceID = "test-microphone"
        value.audio.systemAudioEnabled = true
        value.windowScale = 0.75
        try value.save(defaults: defaults)
        let reopened = RecorderPreferences.load(defaults: defaults)
        #expect(reopened.webcam.selectedDeviceId == "test-camera")
        #expect(reopened.audio.systemAudioEnabled)
        #expect(reopened.windowScale == 0.75)
    }

    @Test func projectPersistenceAndRelativeMediaPaths() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var value = fixtureProject(folder: folder, duration: 8)
        value.edits.pauses = [PauseSuggestion(start: 2, end: 4)]
        try value.save()
        let reopened = try RecordingProject.load(folder: folder)
        #expect(reopened.folder == folder)
        #expect(reopened.edits == value.edits)
        #expect(throws: (any Error).self) { try reopened.mediaURL("../outside.mov") }
        #expect(throws: (any Error).self) { try reopened.mediaURL("/etc/passwd") }
    }

    @Test func structuredAIRefusalsAndInvalidTimesAreRejected() throws {
        let valid = response(zooms: "[{\"start\":1,\"end\":4,\"x\":0.3,\"y\":0.4,\"scale\":1.8,\"reason\":\"Show the button\"}]")
        let parsed = try OpenAIEditor.parseZooms(data: valid, range: MediaRange(start: 0, end: 10))
        #expect(parsed.count == 1 && parsed[0].x == 0.3)
        #expect(throws: (any Error).self) { try OpenAIEditor.parseZooms(data: valid, range: MediaRange(start: 5, end: 10)) }
        let invalid = response(zooms: "[{\"start\":1,\"end\":4,\"x\":3,\"y\":0.4,\"scale\":1.8,\"reason\":\"bad\"}]")
        #expect(throws: (any Error).self) { try OpenAIEditor.parseZooms(data: invalid, range: MediaRange(start: 0, end: 10)) }
        let refusal = Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal"}]}]}"#.utf8)
        #expect(throws: (any Error).self) { try OpenAIEditor.parseZooms(data: refusal, range: MediaRange(start: 0, end: 10)) }
        #expect(throws: (any Error).self) { try OpenAIEditor.parseZooms(data: Data("{}".utf8), range: MediaRange(start: 0, end: 10)) }
    }

    @Test func missingKeyDoesNotReadOrUploadMedia() async {
        let value = fixtureProject(folder: URL(fileURLWithPath: "/unavailable"), duration: 10)
        await #expect(throws: (any Error).self) { try await OpenAIEditor().generate(project: value, key: "", progress: { _ in }) }
    }

    @Test func failedExportLeavesExistingDestinationAndOriginalsUntouched() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("existing.mp4")
        let original = Data("keep existing video".utf8)
        try original.write(to: destination)
        await #expect(throws: (any Error).self) {
            try await ProjectRenderer.export(project: fixtureProject(folder: folder, duration: 10), plan: EditPlan(), to: destination)
        }
        #expect(try Data(contentsOf: destination) == original)
    }

    @Test func exportCannotOverwriteAnOriginalTrack() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("screen.mov")
        let original = Data("preserve original recording".utf8)
        try original.write(to: source)
        do {
            try await ProjectRenderer.export(project: fixtureProject(folder: folder, duration: 10), plan: EditPlan(), to: source)
            Issue.record("Expected protection for the source recording")
        } catch { #expect(error.localizedDescription.contains("original project")) }
        #expect(try Data(contentsOf: source) == original)
    }

    private func response(zooms: String) -> Data {
        let text = "{\"zooms\":\(zooms)}"
        return try! JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]])
    }
}

func fixtureProject(folder: URL, duration: Double) -> RecordingProject {
    var value = RecordingProject(title: "Synthetic integration fixture", webcam: .default, microphoneVolume: 0.8,
        background: SavedBackground(.solidColor(.black)), windowScale: 0.9, width: 320, height: 180,
        frameRate: 10, codec: .h264)
    value.duration = duration; value.state = "complete"; value.folder = folder
    return value
}
