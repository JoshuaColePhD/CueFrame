import SwiftUI
import AVFoundation
import ScreenCaptureKit

struct ReviewDestination: Identifiable {
    let folder: URL
    var id: String { folder.path }
}

struct SetupView: View {
    @State private var preferences = RecorderPreferences.load()
    @State private var background = RecorderPreferences.load().background.style
    @State private var selectedSource: CaptureSource?
    @State private var choosingSource = false
    @State private var showingLibrary = false
    @State private var review: ReviewDestination?
    @State private var pendingProject: URL?
    @State private var message: String?
    @StateObject private var engine = RecordingEngine.shared
    @StateObject private var permissions = PermissionManager.shared
    @StateObject private var sourcePicker = SystemSourcePicker()
    @State private var nativeFilter: SCContentFilter?

    var body: some View {
        NavigationSplitView {
            Form {
                Section("Capture source") {
                    Text(selectedSource?.displayName ?? "Choose a window or display")
                        .font(.headline).lineLimit(2)
                    HStack {
                        Button("Choose window…") { sourcePicker.present(style: .window) }
                        Button("Choose display…") { sourcePicker.present(style: .display) }
                    }
                    Text(nativeFilter != nil ? "Selected content authorized by macOS" : "Choose a source in the macOS sharing picker")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Audio") { AudioSettingsView(configuration: $preferences.audio) }
                Section("Webcam overlay") {
                    Text(permissions.cameraStatus.isGranted ? "Camera access granted" : "Camera access required when overlay is enabled")
                        .font(.caption).foregroundStyle(.secondary)
                    WebcamSettingsView(configuration: $preferences.webcam)
                }
                Section("Appearance") {
                    DisclosureGroup("Background") { BackgroundSelectionView(selectedBackground: $background) }
                    LabeledContent("Screen size", value: "\(Int(preferences.windowScale * 100))%")
                    Slider(value: $preferences.windowScale, in: 0.5...1).accessibilityLabel("Screen size")
                }
                Section("Export quality") {
                    RecordingSettingsView(selectedResolution: $preferences.resolution, selectedCodec: $preferences.codec, frameRate: $preferences.frameRate)
                }
                Section {
                    Text("Original tracks are saved automatically in your recording library. Export a finished video after recording.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .disabled(engine.isRecording)
            .navigationTitle("Record")
            .navigationSplitViewColumnWidth(min: 310, ideal: 350, max: 430)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    if engine.isRecording {
                        VStack(spacing: 16) {
                            Image(systemName: "record.circle").font(.system(size: 54)).foregroundStyle(.red)
                            Text(engine.phase == .recording ? "Recording your demo" : engine.phase == .starting ? engine.startupStatus : "Saving source tracks…")
                                .font(.title2)
                            Text(engine.recordingDuration, format: .number.precision(.fractionLength(1)))
                                .monospacedDigit().font(.title)
                            Text("Screen, webcam and audio are saved independently for editing.")
                                .foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let source = selectedSource {
                        switch source {
                        case .window(let window):
                            WindowPreviewView(window: window, backgroundStyle: background, webcamConfig: $preferences.webcam, windowScale: preferences.windowScale, authorizedFilter: nativeFilter)
                                .id(source.id)
                        case .display(let display):
                            DisplayPreviewView(display: display, backgroundStyle: background, webcamConfig: $preferences.webcam, displayScale: preferences.windowScale, authorizedFilter: nativeFilter)
                                .id(source.id)
                        }
                    } else {
                        ContentUnavailableView {
                            Label("Make a quick demo", systemImage: "rectangle.inset.filled.and.person.filled")
                        } description: {
                            Text("Choose a window or display, check your microphone, then record. Drag the webcam after choosing Custom position.")
                        } actions: {
                            HStack {
                                Button("Choose a window") { sourcePicker.present(style: .window) }.buttonStyle(.borderedProminent)
                                Button("Choose a display") { sourcePicker.present(style: .display) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(engine.isRecording ? engine.phase.rawValue.capitalized : "Ready when you are").font(.headline)
                        Text("\(preferences.audio.microphoneEnabled ? "Voice on" : "Voice off") · \(preferences.webcam.isEnabled ? "Camera on" : "Camera off") · \(preferences.audio.systemAudioEnabled ? "Mac audio on" : "Mac audio off")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if engine.isRecording {
                        Button(engine.canCancelStartup ? "Cancel startup" : "Stop recording", systemImage: "stop.fill") {
                            if engine.canCancelStartup { engine.cancelStartup() }
                            else { Task { _ = await engine.stopRecording() } }
                        }
                            .disabled(engine.phase != .recording && !engine.canCancelStartup)
                            .buttonStyle(.borderedProminent).tint(.red).keyboardShortcut("r", modifiers: [.command, .shift])
                    } else {
                        Button("Start recording", systemImage: "record.circle") { start() }
                            .disabled(selectedSource == nil)
                            .buttonStyle(.borderedProminent).keyboardShortcut("r", modifiers: [.command, .shift])
                    }
                }.padding(20)
            }.navigationTitle("Cueframe")
        }
        .frame(minWidth: 1000, minHeight: 680)
        .toolbar {
            Button("Recordings", systemImage: "film.stack") { showingLibrary = true }.disabled(engine.isRecording)
            SettingsLink { Label("AI settings", systemImage: "sparkles") }.disabled(engine.isRecording)
        }
        .task { await permissions.checkAllPermissions() }
        .onChange(of: sourcePicker.revision) {
            selectedSource = sourcePicker.source; nativeFilter = sourcePicker.filter
        }
        .onChange(of: sourcePicker.failure) { if let failure = sourcePicker.failure { message = failure } }
        .onChange(of: background) { preferences.background = SavedBackground(background) }
        .onChange(of: try? JSONEncoder().encode(preferences)) {
            do { try preferences.save() } catch { message = error.localizedDescription }
        }
        .onChange(of: engine.lastRecordingResult?.id) {
            if let folder = engine.lastRecordingResult?.projectFolder {
                review = ReviewDestination(folder: folder)
                selectedSource = nil; nativeFilter = nil
            }
        }
        .onChange(of: engine.error?.localizedDescription) { if let error = engine.error { message = error.localizedDescription } }
        .sheet(isPresented: $choosingSource, onDismiss: { Task { await permissions.checkAllPermissions() } }) {
            WindowSelectorSheet(selectedSource: $selectedSource)
        }
        .sheet(isPresented: $showingLibrary, onDismiss: {
            if let pendingProject { review = ReviewDestination(folder: pendingProject); self.pendingProject = nil }
        }) {
            RecordingLibraryView { folder in pendingProject = folder; showingLibrary = false }
        }
        .sheet(item: $review) { destination in ProjectReviewView(folder: destination.folder) }
        .alert("Cueframe", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func start() {
        guard let selectedSource else { return }
        var config = RecordingConfiguration(source: selectedSource, background: background, webcam: preferences.webcam,
            audio: preferences.audio, resolution: preferences.resolution, frameRate: preferences.frameRate,
            codec: preferences.codec, outputURL: RecordingProject.root.appendingPathComponent("export.mp4"), windowScale: preferences.windowScale)
        config.authorizedFilter = nativeFilter
        Task {
            do { try await engine.startRecording(configuration: config) }
            catch is CancellationError {}
            catch { message = error.localizedDescription }
        }
    }
}

/// Sheet for source selection
struct WindowSelectorSheet: View {
    @Binding var selectedSource: CaptureSource?
    @Environment(\.dismiss) private var dismiss
    @State private var tempSelection: CaptureSource?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Source")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Source list
            WindowSelectionView(selectedSource: $tempSelection)

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Select") {
                    selectedSource = tempSelection
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tempSelection == nil)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 700, height: 500)
    }
}

#Preview {
    SetupView()
}
