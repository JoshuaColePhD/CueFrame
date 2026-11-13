import SwiftUI
import AVFoundation

struct AudioSettingsView: View {
    @Binding var configuration: AudioConfiguration
    @StateObject private var meter = AudioCaptureService()
    @ObservedObject private var engine = RecordingEngine.shared
    @State private var microphones: [AVCaptureDevice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Record microphone", isOn: $configuration.microphoneEnabled)
            if configuration.microphoneEnabled {
                Picker("Microphone", selection: Binding(get: { configuration.selectedMicrophoneDeviceID ?? "" }, set: { configuration.selectedMicrophoneDeviceID = $0.isEmpty ? nil : $0 })) {
                    Text("System default").tag("")
                    ForEach(microphones, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                    if let id = configuration.selectedMicrophoneDeviceID, !microphones.contains(where: { $0.uniqueID == id }) {
                        Text("Disconnected microphone").tag(id)
                    }
                }
                if meter.hasPermission {
                    ProgressView(value: meter.level)
                        .accessibilityLabel("Microphone input level")
                    Text(meter.isCapturing ? "Microphone meter is listening" : "Microphone permission granted")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Allow microphone and check level") {
                        Task { if await meter.requestMicrophonePermission() { await refresh() } }
                    }
                    Text("Microphone access is required for narration.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Voice volume")
                    Slider(value: $configuration.microphoneVolume, in: 0...1)
                        .accessibilityLabel("Voice volume")
                }
                if let error = meter.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Toggle("Record Mac audio", isOn: $configuration.systemAudioEnabled)
            Text("Mac audio follows the selected capture source. Use headphones to avoid recording speaker sound twice.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await refresh() }
        .onChange(of: configuration.selectedMicrophoneDeviceID) { Task { await refresh() } }
        .onChange(of: configuration.microphoneEnabled) { Task { await refresh() } }
        .onChange(of: engine.isRecording) { Task { await refresh() } }
        .onDisappear { meter.stopCapture() }
    }
    private func refresh() async {
        microphones = meter.getAvailableMicrophones()
        if configuration.microphoneEnabled, !engine.isRecording { await meter.startMeter(deviceID: configuration.selectedMicrophoneDeviceID) }
        else { meter.stopCapture() }
    }
}
