import SwiftUI
import AVKit

struct ProjectReviewView: View {
    @StateObject private var model: ProjectReviewModel
    @Environment(\.dismiss) private var dismiss
    init(folder: URL) { _model = StateObject(wrappedValue: ProjectReviewModel(folder: folder)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.project?.title ?? "Recording").font(.title2).lineLimit(1)
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            HSplitView {
                VStack(spacing: 16) {
                    CustomVideoPlayer(player: model.player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black).clipShape(RoundedRectangle(cornerRadius: 12))
                    HStack {
                        Toggle("Compare original", isOn: $model.original).toggleStyle(.switch).disabled(model.busy)
                        Spacer()
                        if model.previewDirty {
                            Button("Preview changes") { model.refreshPreview() }.disabled(model.busy)
                        }
                    }
                    if let failure = model.project?.failure {
                        Label(failure, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Original screen, camera and audio tracks are kept in this project.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(minWidth: 440)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Edit suggestions").font(.headline)
                        Text("AI reviews sampled screen images and your narration. Review its draft before exporting.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Generate AI Edit", systemImage: "sparkles") { model.generate() }
                            .buttonStyle(.borderedProminent).disabled(model.busy || model.project == nil)
                        Text("Sends screen samples and microphone audio to OpenAI. Uses your API account.")
                            .font(.caption2).foregroundStyle(.secondary)
                        SettingsLink { Label("API key settings", systemImage: "key") }
                        Divider()
                        HStack {
                            Text("Zooms").font(.headline)
                            Spacer()
                            Button("Add") {
                                guard let duration = model.project?.duration else { return }
                                model.plan.zooms.append(ZoomSuggestion(start: 0, end: min(3, duration), x: 0.5, y: 0.5, scale: 1.6, reason: "Manual zoom"))
                            }.disabled(model.busy || model.project == nil)
                        }
                        if model.plan.zooms.isEmpty { Text("No zoom suggestions yet.").font(.caption).foregroundStyle(.secondary) }
                        ForEach($model.plan.zooms) { $zoom in
                            VStack(alignment: .leading, spacing: 9) {
                                Toggle(zoom.reason, isOn: $zoom.enabled).font(.subheadline)
                                HStack {
                                    timeField("Start", value: $zoom.start)
                                    timeField("End", value: $zoom.end)
                                }
                                LabeledContent("Zoom", value: String(format: "%.1f×", zoom.scale))
                                Slider(value: $zoom.scale, in: 1...2.5).accessibilityLabel("Zoom scale")
                                LabeledContent("Target X", value: "\(Int(zoom.x * 100))%")
                                Slider(value: $zoom.x, in: 0...1).accessibilityLabel("Zoom horizontal target")
                                LabeledContent("Target Y", value: "\(Int(zoom.y * 100))%")
                                Slider(value: $zoom.y, in: 0...1).accessibilityLabel("Zoom vertical target")
                            }
                            .padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                            .disabled(model.busy)
                        }
                        Divider()
                        HStack {
                            Text("Pause trims").font(.headline)
                            Spacer()
                            Button("Find locally") { model.findPauses() }.disabled(model.busy || model.project == nil)
                        }
                        Text("Turn a trim off to restore that pause. Speech, screen activity and Mac audio are kept.")
                            .font(.caption).foregroundStyle(.secondary)
                        if model.plan.pauses.isEmpty { Text("No pause trims suggested.").font(.caption).foregroundStyle(.secondary) }
                        ForEach($model.plan.pauses) { $pause in
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(pause.reason, isOn: $pause.enabled)
                                HStack { timeField("Start", value: $pause.start); timeField("End", value: $pause.end) }
                            }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10)).disabled(model.busy)
                        }
                    }.padding(20)
                }.frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
            }
            Divider()
            HStack {
                Button("Show source files", systemImage: "folder") { NSWorkspace.shared.open(model.folder) }
                Spacer()
                if model.busy {
                    if let progress = model.exportProgress { ProgressView(value: progress).frame(width: 140) }
                    else { ProgressView().controlSize(.small) }
                    Button("Cancel") { model.cancel() }
                }
                Button(model.original ? "Export original…" : "Export video…", systemImage: "square.and.arrow.up") { model.export() }
                    .buttonStyle(.borderedProminent).disabled(model.busy || model.project == nil)
            }.padding(20)
        }
        .frame(minWidth: 900, idealWidth: 1120, maxWidth: 1400, minHeight: 650, idealHeight: 780, maxHeight: 1000)
        .task { await model.load() }
        .onChange(of: model.plan) { model.saveEdits() }
        .onChange(of: model.original) { model.refreshPreview() }
        .onDisappear { model.close() }
        .alert("Cueframe", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
    private func timeField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(title) (seconds)").font(.caption).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder).accessibilityLabel("\(title) in seconds")
        }
    }
}

struct RecordingLibraryView: View {
    let open: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var projects: [RecordingProject] = []
    @State private var failure: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Recordings").font(.title2); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(20)
            Divider()
            if let failure { ContentUnavailableView("Could not open library", systemImage: "exclamationmark.triangle", description: Text(failure)) }
            else if projects.isEmpty { ContentUnavailableView("No recordings yet", systemImage: "film.stack", description: Text("Your source tracks and edit drafts will appear here after recording.")) }
            else {
                List(projects) { project in
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(project.title).font(.headline).lineLimit(2)
                            Text("\(project.created.formatted()) · \(Int(project.duration)) seconds · \(project.state)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open") { open(project.folder) }
                    }.padding(.vertical, 6).accessibilityElement(children: .contain)
                }
            }
        }.frame(width: 720, height: 500)
        .task { do { projects = try RecordingProject.library() } catch { failure = error.localizedDescription } }
    }
}
