import SwiftUI
import MetalKit
import AppKit
import simd

struct MetalView: NSViewRepresentable {
    let audio: AudioAnalyzer
    let presets: PresetManager
    let params: ParamStore
    let post: PostSettings

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> KeyCatchingMTKView {
        let view = KeyCatchingMTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true

        let renderer = MetalRenderer(device: view.device!, audio: audio, presets: presets, params: params, post: post)
        view.delegate = renderer
        context.coordinator.renderer = renderer
        context.coordinator.presets = presets
        view.onPointer = { [weak renderer] point, isDown, clicked in
            renderer?.pointerMoved(to: point, isDown: isDown, clicked: clicked)
        }
        view.onPointerExit = { [weak renderer] in
            renderer?.pointerExited()
        }
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
    var onPointer: ((SIMD2<Float>, Bool, Bool) -> Void)?
    var onPointerExit: (() -> Void)?
    private var pointerTrackingArea: NSTrackingArea?

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

    override func mouseMoved(with event: NSEvent) {
        onPointer?(normalizedPoint(from: event), false, false)
        super.mouseMoved(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        onPointer?(normalizedPoint(from: event), true, true)
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        onPointer?(normalizedPoint(from: event), true, false)
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        onPointer?(normalizedPoint(from: event), false, false)
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onPointer?(normalizedPoint(from: event), true, true)
        super.rightMouseDown(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        onPointer?(normalizedPoint(from: event), true, false)
        super.rightMouseDragged(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        onPointer?(normalizedPoint(from: event), false, false)
        super.rightMouseUp(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self)
        pointerTrackingArea = area
        addTrackingArea(area)
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExit?()
        super.mouseExited(with: event)
    }

    private func normalizedPoint(from event: NSEvent) -> SIMD2<Float> {
        let location = convert(event.locationInWindow, from: nil)
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let x = Float(min(max(location.x / width, 0), 1))
        let rawY = Float(min(max(location.y / height, 0), 1))
        let y = isFlipped ? rawY : 1.0 - rawY
        return SIMD2<Float>(x, y)
    }
}
