import Foundation
import MetalKit
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

    private var currentPresetId: String?
    private var currentPipeline: MTLRenderPipelineState?
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]

    private let spectrumTexture: MTLTexture
    private let waveformTexture: MTLTexture

    init(device: MTLDevice, audio: AudioAnalyzer, presets: PresetManager, params: ParamStore) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.library = device.makeDefaultLibrary()!
        self.audio = audio
        self.presets = presets
        self.params = params

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

    private func pipeline(for preset: Preset, view: MTKView) -> MTLRenderPipelineState? {
        if let cached = pipelineCache[preset.id] { return cached }
        guard let vFn = library.makeFunction(name: "vertex_fullscreen"),
              let fFn = library.makeFunction(name: preset.fragmentFunction) else {
            NSLog("MusicViz: missing shader for \(preset.id)")
            return nil
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vFn
        desc.fragmentFunction = fFn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        do {
            let p = try device.makeRenderPipelineState(descriptor: desc)
            pipelineCache[preset.id] = p
            return p
        } catch {
            NSLog("MusicViz: pipeline build failed for \(preset.id): \(error)")
            return nil
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let preset = presets.current
        if currentPresetId != preset.id {
            currentPipeline = pipeline(for: preset, view: view)
            currentPresetId = preset.id
        }
        guard let pipeline = currentPipeline,
              let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return }

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

        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<AudioUniforms>.stride, index: 0)
        enc.setFragmentBytes(&p, length: MemoryLayout<PresetParams>.stride, index: 1)
        enc.setFragmentTexture(spectrumTexture, index: 0)
        enc.setFragmentTexture(waveformTexture, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()
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
}
