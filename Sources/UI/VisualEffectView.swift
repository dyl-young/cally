import SwiftUI
import AppKit

/// SwiftUI wrapper around NSVisualEffectView so we can use system materials (e.g. .menu) as a
/// view background. macOS-only.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = state
        v.isEmphasized = false
        return v
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
    }
}
