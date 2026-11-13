import AppKit
import ScreenCaptureKit
import Combine

@MainActor
final class WindowPreview: ObservableObject {
    @Published var previewImage: CGImage?
    @Published var isCapturing = false
    @Published var failure: String?

    func capturePreview(window: WindowInfo, authorizedFilter: SCContentFilter? = nil) async {
        if let authorizedFilter { await capture(filter: authorizedFilter); return }
        guard let value = window.scWindow else { failure = "Choose the window again."; return }
        await capture(filter: SCContentFilter(desktopIndependentWindow: value))
    }
    func capturePreview(display: DisplayInfo, authorizedFilter: SCContentFilter? = nil) async {
        if let authorizedFilter { await capture(filter: authorizedFilter); return }
        guard let value = display.scDisplay else { failure = "Choose the display again."; return }
        await capture(filter: SCContentFilter(display: value, excludingWindows: []))
    }
    private func capture(filter: SCContentFilter) async {
        guard !isCapturing else { return }
        isCapturing = true; failure = nil
        defer { isCapturing = false }
        do {
            let configuration = SCStreamConfiguration()
            let scale = min(1, 1920 / max(filter.contentRect.width * CGFloat(filter.pointPixelScale), 1))
            configuration.width = max(2, Int(filter.contentRect.width * CGFloat(filter.pointPixelScale) * scale))
            configuration.height = max(2, Int(filter.contentRect.height * CGFloat(filter.pointPixelScale) * scale))
            configuration.showsCursor = false
            previewImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch { failure = error.localizedDescription }
    }
}
