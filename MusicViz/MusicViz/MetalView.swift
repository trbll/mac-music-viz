import SwiftUI
import MetalKit
import AppKit

struct MetalView: NSViewRepresentable {
    let audio: AudioAnalyzer
    let presets: PresetManager
    let params: ParamStore

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> KeyCatchingMTKView {
        let view = KeyCatchingMTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true

        let renderer = MetalRenderer(device: view.device!, audio: audio, presets: presets, params: params)
        view.delegate = renderer
        context.coordinator.renderer = renderer
        context.coordinator.presets = presets
        view.onKey = { [weak presets] event in
            guard let presets else { return false }
            switch event.keyCode {
            case 123: presets.prev(); return true       // left arrow
            case 124: presets.next(); return true       // right arrow
            case 49:  presets.next(); return true       // space
            default:  return false
            }
        }
        return view
    }

    func updateNSView(_ nsView: KeyCatchingMTKView, context: Context) {}

    final class Coordinator {
        var renderer: MetalRenderer?
        var presets: PresetManager?
    }
}

final class KeyCatchingMTKView: MTKView {
    var onKey: ((NSEvent) -> Bool)?
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if let h = onKey, h(event) { return }
        super.keyDown(with: event)
    }
}
