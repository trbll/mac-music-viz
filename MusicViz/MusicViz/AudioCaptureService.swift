import Foundation
import ScreenCaptureKit
import AVFoundation
import OSLog

final class AudioCaptureService: NSObject, ObservableObject, @unchecked Sendable {
    @Published var isRunning = false
    @Published var errorMessage: String?

    private weak var analyzer: AudioAnalyzer?
    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "MusicViz.SCStream.audio", qos: .userInteractive)
    private let log = Logger(subsystem: "MusicViz", category: "AudioCapture")

    init(analyzer: AudioAnalyzer) {
        self.analyzer = analyzer
        super.init()
    }

    func start() async {
        if await MainActor.run(body: { self.isRunning }) { return }
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                throw NSError(domain: "MusicViz", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "No display available"])
            }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 8)
            config.showsCursor = false

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            // We must add a video output too or the stream fails to start on some macOS versions.
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)

            try await stream.startCapture()
            self.stream = stream
            await MainActor.run {
                self.isRunning = true
                self.errorMessage = nil
            }
            log.info("Audio capture started")
        } catch {
            let msg = error.localizedDescription
            await MainActor.run {
                self.errorMessage = msg
                self.isRunning = false
            }
            log.error("Audio capture failed: \(msg, privacy: .public)")
        }
    }

    func stop() async {
        guard let stream else { return }
        do { try await stream.stopCapture() } catch {
            log.error("Stop failed: \(error.localizedDescription, privacy: .public)")
        }
        self.stream = nil
        await MainActor.run { self.isRunning = false }
    }
}

extension AudioCaptureService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let msg = error.localizedDescription
        Task { @MainActor in
            self.errorMessage = msg
            self.isRunning = false
        }
    }
}

extension AudioCaptureService: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let samples = extractMonoFloatSamples(from: sampleBuffer) else { return }
        analyzer?.push(samples: samples, sampleRate: 48000)
    }
}

private func extractMonoFloatSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
    guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
          let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
        return nil
    }
    let asbd = asbdPtr.pointee
    let frameCount = Int(CMSampleBufferGetNumSamples(sampleBuffer))
    guard frameCount > 0 else { return nil }
    let channels = Int(asbd.mChannelsPerFrame)
    let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
    guard isFloat, channels >= 1 else { return nil }

    var listSize = 0
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sampleBuffer,
        bufferListSizeNeededOut: &listSize,
        bufferListOut: nil,
        bufferListSize: 0,
        blockBufferAllocator: nil,
        blockBufferMemoryAllocator: nil,
        flags: 0,
        blockBufferOut: nil
    )
    guard listSize > 0 else { return nil }

    let listPtr = UnsafeMutableRawPointer.allocate(
        byteCount: listSize,
        alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { listPtr.deallocate() }
    let abl = listPtr.assumingMemoryBound(to: AudioBufferList.self)

    var blockBuffer: CMBlockBuffer?
    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sampleBuffer,
        bufferListSizeNeededOut: nil,
        bufferListOut: abl,
        bufferListSize: listSize,
        blockBufferAllocator: nil,
        blockBufferMemoryAllocator: nil,
        flags: 0,
        blockBufferOut: &blockBuffer
    )
    guard status == noErr else { return nil }

    let bufferList = UnsafeMutableAudioBufferListPointer(abl)
    var mono = [Float](repeating: 0, count: frameCount)

    if isNonInterleaved {
        let count = bufferList.count
        for ch in 0..<count {
            guard let raw = bufferList[ch].mData else { continue }
            let ptr = raw.assumingMemoryBound(to: Float.self)
            for i in 0..<frameCount { mono[i] += ptr[i] }
        }
        let scale = Float(1.0) / Float(max(count, 1))
        for i in 0..<frameCount { mono[i] *= scale }
    } else {
        guard let raw = bufferList[0].mData else { return nil }
        let ptr = raw.assumingMemoryBound(to: Float.self)
        let scale = Float(1.0) / Float(channels)
        for i in 0..<frameCount {
            var sum: Float = 0
            for ch in 0..<channels { sum += ptr[i * channels + ch] }
            mono[i] = sum * scale
        }
    }
    return mono
}
