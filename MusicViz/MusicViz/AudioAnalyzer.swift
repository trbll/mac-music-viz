import Foundation
import Accelerate
import QuartzCore

struct AudioState {
    var time: Float = 0
    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var loudness: Float = 0
    var beat: Float = 0
    var spectrum: [Float] = Array(repeating: 0, count: AudioAnalyzer.spectrumBinCount)
    var waveform: [Float] = Array(repeating: 0, count: AudioAnalyzer.waveformSize)
}

final class AudioAnalyzer: @unchecked Sendable {
    static let fftSize = 2048
    static let halfSize = fftSize / 2
    static let spectrumBinCount = 128
    static let waveformSize = 256

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let window: [Float]

    private let ringLock = NSLock()
    private var ring = [Float](repeating: 0, count: fftSize * 4)
    private var ringWrite = 0
    private var ringFilled = 0

    private let stateLock = NSLock()
    private var state = AudioState()

    private var energyHistory = [Float](repeating: 0, count: 43)
    private var energyHistoryIndex = 0
    private var lastAnalyzeTime: CFTimeInterval = 0
    private let startTime = CACurrentMediaTime()

    init() {
        self.log2n = vDSP_Length(log2(Double(Self.fftSize)).rounded())
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        var hann = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&hann, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        self.window = hann
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    func snapshot() -> AudioState {
        stateLock.lock(); defer { stateLock.unlock() }
        var s = state
        s.time = Float(CACurrentMediaTime() - startTime)
        return s
    }

    func push(samples: [Float], sampleRate: Double) {
        ringLock.lock()
        let n = samples.count
        for i in 0..<n {
            ring[ringWrite] = samples[i]
            ringWrite = (ringWrite + 1) % ring.count
        }
        ringFilled = min(ring.count, ringFilled + n)
        ringLock.unlock()

        // Throttle FFT to ~60Hz max
        let now = CACurrentMediaTime()
        if now - lastAnalyzeTime < 1.0 / 90.0 { return }
        lastAnalyzeTime = now

        guard ringFilled >= Self.fftSize else { return }
        analyze(sampleRate: sampleRate)
    }

    private func analyze(sampleRate: Double) {
        var frame = [Float](repeating: 0, count: Self.fftSize)
        ringLock.lock()
        var idx = (ringWrite - Self.fftSize + ring.count) % ring.count
        for i in 0..<Self.fftSize {
            frame[i] = ring[idx]
            idx = (idx + 1) % ring.count
        }
        ringLock.unlock()

        // Time-domain RMS (before windowing)
        var rms: Float = 0
        vDSP_rmsqv(frame, 1, &rms, vDSP_Length(Self.fftSize))

        // Downsample waveform for shader (pre-window)
        var wave = [Float](repeating: 0, count: Self.waveformSize)
        let step = Self.fftSize / Self.waveformSize
        for i in 0..<Self.waveformSize { wave[i] = frame[i * step] }

        // Window
        vDSP.multiply(frame, window, result: &frame)

        // Real FFT via split-complex packing
        var realp = [Float](repeating: 0, count: Self.halfSize)
        var imagp = [Float](repeating: 0, count: Self.halfSize)
        var mags = [Float](repeating: 0, count: Self.halfSize)

        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeBufferPointer { fp in
                    fp.baseAddress!.withMemoryRebound(to: DSPComplex.self,
                                                      capacity: Self.halfSize) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(Self.halfSize))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(Self.halfSize))
            }
        }

        // Normalize and perceptual compress
        let norm = Float(1.0) / Float(Self.fftSize)
        for i in 0..<Self.halfSize {
            mags[i] = sqrtf(mags[i] * norm)
        }

        // Log-spaced downsample to spectrumBinCount
        var smoothed = [Float](repeating: 0, count: Self.spectrumBinCount)
        let maxBin = Float(Self.halfSize - 1)
        for i in 0..<Self.spectrumBinCount {
            let t0 = Float(i) / Float(Self.spectrumBinCount)
            let t1 = Float(i + 1) / Float(Self.spectrumBinCount)
            let lo = max(0, min(Int(powf(maxBin, t0)), Self.halfSize - 1))
            let hi = max(lo, min(Int(powf(maxBin, t1)), Self.halfSize - 1))
            var peak: Float = 0
            for b in lo...hi { peak = max(peak, mags[b]) }
            smoothed[i] = peak
        }

        // Band energies (linear Hz cutoffs)
        let nyquist = Float(sampleRate) * 0.5
        let binHz = nyquist / Float(Self.halfSize)
        let bassEnd = min(Self.halfSize, max(1, Int(200 / binHz)))
        let midEnd = min(Self.halfSize, max(bassEnd + 1, Int(2000 / binHz)))
        var bassE: Float = 0, midE: Float = 0, trebleE: Float = 0
        for i in 0..<bassEnd { bassE += mags[i] }
        for i in bassEnd..<midEnd { midE += mags[i] }
        for i in midEnd..<Self.halfSize { trebleE += mags[i] }
        bassE /= Float(bassEnd)
        midE /= Float(max(1, midEnd - bassEnd))
        trebleE /= Float(max(1, Self.halfSize - midEnd))

        // Beat via bass energy vs moving average
        let avgE = energyHistory.reduce(0, +) / Float(energyHistory.count)
        energyHistory[energyHistoryIndex] = bassE
        energyHistoryIndex = (energyHistoryIndex + 1) % energyHistory.count
        let onset = max(0, bassE - avgE * 1.3) / max(avgE, 1e-4)
        let beatInstant = min(1.0, onset)

        // Commit to state with smoothing
        stateLock.lock()
        var newSpec = state.spectrum
        for i in 0..<Self.spectrumBinCount {
            newSpec[i] = max(smoothed[i], newSpec[i] * 0.82)
        }
        state.spectrum = newSpec
        state.waveform = wave
        state.bass = smoothScalar(prev: state.bass, next: clamp01(bassE * 6), up: 0.55, down: 0.15)
        state.mid = smoothScalar(prev: state.mid, next: clamp01(midE * 6), up: 0.55, down: 0.15)
        state.treble = smoothScalar(prev: state.treble, next: clamp01(trebleE * 6), up: 0.55, down: 0.15)
        state.loudness = smoothScalar(prev: state.loudness, next: clamp01(rms * 4), up: 0.55, down: 0.1)
        state.beat = max(beatInstant, state.beat * 0.88)
        stateLock.unlock()
    }

    private func smoothScalar(prev: Float, next: Float, up: Float, down: Float) -> Float {
        let factor = next > prev ? up : down
        return prev + (next - prev) * factor
    }

    private func clamp01(_ x: Float) -> Float { min(1.0, max(0.0, x)) }
}
