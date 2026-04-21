import Foundation
import MetalKit
import QuartzCore
import simd

struct AudioUniforms {
    var time: Float = 0
    var beat: Float = 0
    var resolution: SIMD2<Float> = .zero
    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var loudness: Float = 0
}

final class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary

    private let audio: AudioAnalyzer
    private let presets: PresetManager
    private let params: ParamStore
    private let post: PostSettings

    private var currentPresetId: String?
    private var currentPipeline: MTLRenderPipelineState?
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]
    private var postPipeline: MTLRenderPipelineState?
    private var copyPipeline: MTLRenderPipelineState?
    private var copyPipelineFormat: MTLPixelFormat?

    private let spectrumTexture: MTLTexture
    private let waveformTexture: MTLTexture
    private var sceneTexture: MTLTexture?
    private var historyReadTexture: MTLTexture?
    private var historyWriteTexture: MTLTexture?
    private var historyValid = false

    private let scenePixelFormat: MTLPixelFormat = .rgba16Float

    private var pointerPosition = SIMD2<Float>(0.5, 0.5)
    private var previousPointerPosition = SIMD2<Float>(0.5, 0.5)
    private var pointerVelocity = SIMD2<Float>.zero
    private var dragStart = SIMD2<Float>(0.5, 0.5)
    private var pointerIsDown = false
    private var pointerIsInside = false
    private var clickPulse: Float = 0
    private var lastPointerEventTime = CACurrentMediaTime() - 999
    private var lastDrawTime = CACurrentMediaTime()

    init(device: MTLDevice, audio: AudioAnalyzer, presets: PresetManager, params: ParamStore, post: PostSettings) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.library = device.makeDefaultLibrary()!
        self.audio = audio
        self.presets = presets
        self.params = params
        self.post = post

        let specDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: AudioAnalyzer.spectrumBinCount,
            height: 1,
            mipmapped: false
        )
        specDesc.usage = [.shaderRead]
        self.spectrumTexture = device.makeTexture(descriptor: specDesc)!

        let waveDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: AudioAnalyzer.waveformSize,
            height: 1,
            mipmapped: false
        )
        waveDesc.usage = [.shaderRead]
        self.waveformTexture = device.makeTexture(descriptor: waveDesc)!

        super.init()
    }

    private func pipeline(for preset: Preset) -> MTLRenderPipelineState? {
        if let cached = pipelineCache[preset.id] { return cached }
        guard let vFn = library.makeFunction(name: "vertex_fullscreen"),
              let fFn = library.makeFunction(name: preset.fragmentFunction) else {
            NSLog("MusicViz: missing shader for \(preset.id)")
            return nil
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vFn
        desc.fragmentFunction = fFn
        desc.colorAttachments[0].pixelFormat = scenePixelFormat
        do {
            let p = try device.makeRenderPipelineState(descriptor: desc)
            pipelineCache[preset.id] = p
            return p
        } catch {
            NSLog("MusicViz: pipeline build failed for \(preset.id): \(error)")
            return nil
        }
    }

    private func fullscreenPipeline(fragmentFunction: String, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        guard let vFn = library.makeFunction(name: "vertex_fullscreen"),
              let fFn = library.makeFunction(name: fragmentFunction) else {
            NSLog("MusicViz: missing shader for \(fragmentFunction)")
            return nil
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vFn
        desc.fragmentFunction = fFn
        desc.colorAttachments[0].pixelFormat = pixelFormat
        do {
            return try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            NSLog("MusicViz: pipeline build failed for \(fragmentFunction): \(error)")
            return nil
        }
    }

    private func ensurePostPipelines(view: MTKView) {
        if postPipeline == nil {
            postPipeline = fullscreenPipeline(fragmentFunction: "fragment_post", pixelFormat: scenePixelFormat)
        }
        if copyPipeline == nil || copyPipelineFormat != view.colorPixelFormat {
            copyPipeline = fullscreenPipeline(fragmentFunction: "fragment_copy", pixelFormat: view.colorPixelFormat)
            copyPipelineFormat = view.colorPixelFormat
        }
    }

    private func ensureMultipassTextures(view: MTKView) {
        let width = max(1, Int(view.drawableSize.width.rounded(.up)))
        let height = max(1, Int(view.drawableSize.height.rounded(.up)))
        if sceneTexture?.width == width,
           sceneTexture?.height == height,
           sceneTexture?.pixelFormat == scenePixelFormat {
            return
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: scenePixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private

        sceneTexture = device.makeTexture(descriptor: desc)
        historyReadTexture = device.makeTexture(descriptor: desc)
        historyWriteTexture = device.makeTexture(descriptor: desc)
        sceneTexture?.label = "MusicViz scene"
        historyReadTexture?.label = "MusicViz history read"
        historyWriteTexture?.label = "MusicViz history write"
        historyValid = false
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        historyValid = false
    }

    func pointerMoved(to point: SIMD2<Float>, isDown: Bool, clicked: Bool) {
        let now = CACurrentMediaTime()
        let dt = max(Float(now - lastPointerEventTime), 1.0 / 240.0)
        let clamped = SIMD2<Float>(
            min(max(point.x, 0), 1),
            min(max(point.y, 0), 1)
        )

        previousPointerPosition = pointerPosition
        pointerPosition = clamped
        let instantVelocity = (pointerPosition - previousPointerPosition) / dt
        pointerVelocity = pointerVelocity * 0.55 + instantVelocity * 0.45
        pointerIsDown = isDown
        pointerIsInside = true
        if clicked {
            dragStart = pointerPosition
            clickPulse = 1
        }
        lastPointerEventTime = now
    }

    func pointerExited() {
        pointerIsInside = false
    }

    func draw(in view: MTKView) {
        let preset = presets.current
        if currentPresetId != preset.id {
            currentPipeline = pipeline(for: preset)
            currentPresetId = preset.id
            historyValid = false
        }
        ensurePostPipelines(view: view)
        ensureMultipassTextures(view: view)

        guard let pipeline = currentPipeline,
              let postPipeline,
              let copyPipeline,
              let sceneTexture,
              let historyReadTexture,
              let historyWriteTexture,
              let drawable = view.currentDrawable,
              let drawablePass = view.currentRenderPassDescriptor,
              let cmdBuf = commandQueue.makeCommandBuffer() else { return }

        let state = audio.snapshot()
        upload(spectrum: state.spectrum, to: spectrumTexture)
        upload(spectrum: state.waveform, to: waveformTexture)

        let size = view.drawableSize
        var u = AudioUniforms(
            time: state.time,
            beat: state.beat,
            resolution: SIMD2<Float>(Float(size.width), Float(size.height)),
            bass: state.bass,
            mid: state.mid,
            treble: state.treble,
            loudness: state.loudness
        )
        var p = params.packed(for: preset)
        var i = interactionUniforms(now: CACurrentMediaTime())
        var postUniforms = post.uniforms(for: preset.id, resolution: u.resolution, historyReady: historyValid)

        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = sceneTexture
        scenePass.colorAttachments[0].loadAction = .clear
        scenePass.colorAttachments[0].storeAction = .store
        scenePass.colorAttachments[0].clearColor = view.clearColor

        guard let sceneEnc = cmdBuf.makeRenderCommandEncoder(descriptor: scenePass) else { return }
        sceneEnc.setRenderPipelineState(pipeline)
        sceneEnc.setFragmentBytes(&u, length: MemoryLayout<AudioUniforms>.stride, index: 0)
        sceneEnc.setFragmentBytes(&p, length: MemoryLayout<PresetParams>.stride, index: 1)
        sceneEnc.setFragmentBytes(&i, length: MemoryLayout<InteractionUniforms>.stride, index: 2)
        sceneEnc.setFragmentTexture(spectrumTexture, index: 0)
        sceneEnc.setFragmentTexture(waveformTexture, index: 1)
        sceneEnc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        sceneEnc.endEncoding()

        let postPass = MTLRenderPassDescriptor()
        postPass.colorAttachments[0].texture = historyWriteTexture
        postPass.colorAttachments[0].loadAction = .clear
        postPass.colorAttachments[0].storeAction = .store
        postPass.colorAttachments[0].clearColor = view.clearColor

        guard let postEnc = cmdBuf.makeRenderCommandEncoder(descriptor: postPass) else { return }
        postEnc.setRenderPipelineState(postPipeline)
        postEnc.setFragmentBytes(&u, length: MemoryLayout<AudioUniforms>.stride, index: 0)
        postEnc.setFragmentBytes(&postUniforms, length: MemoryLayout<PostUniforms>.stride, index: 1)
        postEnc.setFragmentBytes(&i, length: MemoryLayout<InteractionUniforms>.stride, index: 2)
        postEnc.setFragmentTexture(sceneTexture, index: 0)
        postEnc.setFragmentTexture(historyReadTexture, index: 1)
        postEnc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        postEnc.endEncoding()

        guard let copyEnc = cmdBuf.makeRenderCommandEncoder(descriptor: drawablePass) else { return }
        copyEnc.setRenderPipelineState(copyPipeline)
        copyEnc.setFragmentTexture(historyWriteTexture, index: 0)
        copyEnc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        copyEnc.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()

        swap(&self.historyReadTexture, &self.historyWriteTexture)
        historyValid = true
    }

    private func upload(spectrum: [Float], to texture: MTLTexture) {
        guard !spectrum.isEmpty else { return }
        let region = MTLRegionMake2D(0, 0, texture.width, 1)
        spectrum.withUnsafeBufferPointer { ptr in
            texture.replace(region: region,
                            mipmapLevel: 0,
                            withBytes: ptr.baseAddress!,
                            bytesPerRow: MemoryLayout<Float>.size * texture.width)
        }
    }

    private func interactionUniforms(now: CFTimeInterval) -> InteractionUniforms {
        let frameDelta = max(Float(now - lastDrawTime), 1.0 / 240.0)
        lastDrawTime = now

        clickPulse *= pow(0.08, frameDelta)
        pointerVelocity *= pow(0.04, frameDelta)

        let idle = Float(max(0, now - lastPointerEventTime))
        let active = pointerIsInside || pointerIsDown || idle < 2.5
        return InteractionUniforms(
            mouse: pointerPosition,
            previousMouse: previousPointerPosition,
            velocity: pointerVelocity,
            dragStart: dragStart,
            isActive: active ? 1 : 0,
            isDown: pointerIsDown ? 1 : 0,
            clickPulse: clickPulse,
            idleTime: idle
        )
    }
}
