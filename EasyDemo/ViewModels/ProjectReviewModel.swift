import AppKit
import AVKit
import Combine

@MainActor
final class ProjectReviewModel: ObservableObject {
    let folder: URL
    @Published var project: RecordingProject?
    @Published var plan = EditPlan()
    @Published var player = AVPlayer()
    @Published var original = false
    @Published var previewDirty = false
    @Published var busy = false
    @Published var status = "Opening recording…"
    @Published var message: String?
    @Published var exportProgress: Float?
    private var operation: Task<Void, Never>?

    init(folder: URL) { self.folder = folder }
    func load() async {
        busy = true
        defer { busy = false }
        do {
            var value = try RecordingProject.load(folder: folder)
            if value.duration <= 0 || value.state == "recording" {
                let asset = AVURLAsset(url: try value.mediaURL(value.screenFile))
                value.duration = try await asset.load(.duration).seconds
                guard value.duration.isFinite, value.duration > 0 else { throw EditingError.noScreen }
                value.state = "interrupted"
                value.failure = "The previous session did not close normally. Available source tracks have been kept."
                try value.save()
            }
            project = value; plan = value.edits
            try await updatePreview()
        } catch { message = error.localizedDescription; status = "Could not open the preview. Source files are preserved." }
    }

    func saveEdits() {
        guard var value = project else { return }
        value.edits = plan
        do { try value.save(); project = value; previewDirty = true }
        catch { message = "Could not save edits: \(error.localizedDescription)" }
    }
    func refreshPreview() {
        guard !busy else { return }
        busy = true
        operation = Task {
            defer { busy = false }
            do { try await updatePreview() }
            catch { handle(error) }
        }
    }
    private func updatePreview() async throws {
        guard let project else { return }
        status = "Preparing preview…"
        let rendered = try await ProjectRenderer.build(project: project, plan: original ? EditPlan() : plan)
        try Task.checkCancellation()
        player.pause(); player.replaceCurrentItem(with: rendered.playerItem)
        previewDirty = false; status = original ? "Original recording" : "Edited preview"
    }
    func findPauses() {
        guard let project else { return }
        plan.pauses = PauseDetector.suggestions(samples: project.activity, cursor: project.cursor, duration: project.duration,
            microphone: project.microphoneFile != nil, system: project.systemAudioFile != nil)
        status = plan.pauses.isEmpty ? "No safe pause trims found" : "Pause suggestions ready to review"
    }
    func generate() {
        guard !busy, let project else { return }
        do {
            guard let key = try OpenAIKeyStore.load(), !key.isEmpty else { throw EditingError.missingKey }
            busy = true; status = "Preparing AI edit…"
            operation = Task {
                defer { busy = false }
                do {
                    // Reopen to reuse transcript checkpoints from an interrupted request.
                    var value = try RecordingProject.load(folder: folder)
                    value.edits = plan
                    let (edits, transcript) = try await OpenAIEditor().generate(project: value, key: key) { [weak self] text in
                        Task { @MainActor [weak self] in self?.status = text }
                    }
                    try Task.checkCancellation()
                    value.transcript = transcript; value.edits = edits; try value.save()
                    self.project = value; plan = edits; original = false
                    try await updatePreview()
                    status = "AI draft ready · review suggestions before export"
                } catch { handle(error) }
            }
        } catch { handle(error) }
        _ = project
    }

    func export() {
        guard !busy, let project else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = project.codec == .h264 ? [.mpeg4Movie] : [.quickTimeMovie]
        panel.nameFieldStringValue = "EasyDemo-\(project.created.formatted(.iso8601).replacingOccurrences(of: ":", with: "-"))\(original ? "-original" : "").\(project.codec == .h264 ? "mp4" : "mov")"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let access = destination.startAccessingSecurityScopedResource()
        let edit = original ? EditPlan() : plan
        busy = true; status = "Exporting video…"; exportProgress = 0; player.pause()
        operation = Task {
            defer { busy = false; exportProgress = nil; if access { destination.stopAccessingSecurityScopedResource() } }
            do {
                try await ProjectRenderer.export(project: project, plan: edit, to: destination) { [weak self] amount in
                    Task { @MainActor [weak self] in self?.exportProgress = amount }
                }
                status = "Exported \(destination.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch { handle(error) }
        }
    }
    func cancel() { operation?.cancel(); status = "Cancelled · original tracks are safe" }
    func close() { operation?.cancel(); player.pause() }
    private func handle(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { status = "Cancelled · original tracks are safe" }
        else { message = error.localizedDescription; status = "Operation failed · original tracks are safe" }
    }
}
