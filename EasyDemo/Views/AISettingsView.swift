import SwiftUI

struct AISettingsView: View {
    @State private var key = ""
    @State private var status = ""
    @State private var saved = false
    var body: some View {
        Form {
            Section("OpenAI editing") {
                Text("Generate smooth zooms and pause suggestions after recording. Capture and export work offline.")
                SecureField("OpenAI API key", text: $key)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save key in Keychain") {
                        do { try OpenAIKeyStore.save(key); key = ""; saved = true; status = "Key saved in macOS Keychain." }
                        catch { status = error.localizedDescription }
                    }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove saved key", role: .destructive) {
                        do { try OpenAIKeyStore.remove(); saved = false; status = "Key removed." }
                        catch { status = error.localizedDescription }
                    }.disabled(!saved)
                }
                Text(status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("keyStatus")
            }
            Section("What is sent") {
                Text("Only when you choose Generate AI Edit, sampled screen images, click positions, and microphone audio are sent directly to OpenAI. Camera video and Mac audio remain on your Mac. API usage is billed to your OpenAI account.")
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Screen analysis", value: "gpt-6.1-sol")
                LabeledContent("Narration", value: "gpt-transcribe")
            }
        }
        .formStyle(.grouped)
        .frame(width: 550, height: 410)
        .onAppear {
            do { saved = try OpenAIKeyStore.load() != nil; status = saved ? "An API key is saved in Keychain." : "No API key saved." }
            catch { status = error.localizedDescription }
        }
    }
}
