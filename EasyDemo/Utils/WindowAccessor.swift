import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.minSize = NSSize(width: 1000, height: 680)
            window.setContentSize(NSSize(width: 1280, height: 820))
            window.center()
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
