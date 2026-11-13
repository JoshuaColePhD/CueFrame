import ScreenCaptureKit
import Combine

/// The system picker authorizes only the content explicitly selected by the user.
@MainActor
final class SystemSourcePicker: NSObject, ObservableObject, SCContentSharingPickerObserver {
    @Published var source: CaptureSource?
    @Published var failure: String?
    @Published var revision = UUID()
    private(set) var filter: SCContentFilter?

    override init() {
        super.init()
        SCContentSharingPicker.shared.add(self)
    }
    func present(style: SCShareableContentStyle = .window) {
        failure = nil
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = style == .display ? [.singleDisplay] : [.singleWindow]
        config.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "com.joshuacole.easydemo"]
        config.allowsChangingSelectedContent = false
        let picker = SCContentSharingPicker.shared
        picker.defaultConfiguration = config
        picker.maximumStreamCount = 1
        picker.isActive = true
        picker.present(using: style)
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {}
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in self?.failure = error.localizedDescription }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.filter = filter
            if filter.style == .window, let window = filter.includedWindows.first {
                self.source = .window(WindowInfo(id: window.windowID, ownerName: window.owningApplication?.applicationName ?? "Window",
                    windowName: window.title, bounds: window.frame, layer: Int(window.windowLayer), alpha: 1, scWindow: window))
            } else if let display = filter.includedDisplays.first {
                self.source = .display(DisplayInfo(id: display.displayID, width: display.width, height: display.height, scDisplay: display))
            } else { self.failure = "macOS did not return a window or display. Choose a source again." }
            self.revision = UUID()
        }
    }
}
