import SwiftUI

struct ContentView: View {
    @StateObject private var audio: AudioAnalyzer_Observable
    @StateObject private var capture: AudioCaptureService
    @StateObject private var presets: PresetManager
    @StateObject private var params: ParamStore
    @StateObject private var post: PostSettings
    @StateObject private var imageSource: ImageSourceStore

    @State private var overlayVisible = true
    @State private var hideOverlayTask: Task<Void, Never>?
    @State private var panelOpen = false
    @State private var mouseMonitor: Any?

    init() {
        let a = AudioAnalyzer_Observable()
        let pm = PresetManager()
        _audio = StateObject(wrappedValue: a)
        _capture = StateObject(wrappedValue: AudioCaptureService(analyzer: a.analyzer))
        _presets = StateObject(wrappedValue: pm)
        _params = StateObject(wrappedValue: ParamStore())
        _post = StateObject(wrappedValue: PostSettings())
        _imageSource = StateObject(wrappedValue: ImageSourceStore())
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MetalView(audio: audio.analyzer, presets: presets, params: params, post: post, imageSource: imageSource)
                .ignoresSafeArea()
                .background(Color.black)

            overlayLayer

            if panelOpen {
                ConfigPanel(presets: presets, params: params, post: post, imageSource: imageSource) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        panelOpen = false
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .contentShape(Rectangle())
        .onAppear {
            Task { await capture.start() }
            bumpOverlay()
            installMouseMonitor()
        }
        .onDisappear {
            Task { await capture.stop() }
            removeMouseMonitor()
        }
        .onChange(of: presets.index) { _, _ in bumpOverlay() }
        .background(
            // Hidden button to get ⌘, shortcut wired without a menu bar item
            Button("") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    panelOpen.toggle()
                }
            }
            .keyboardShortcut(",", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
    }

    private var overlayLayer: some View {
        VStack {
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    Text(presets.current.name)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text("\(presets.index + 1)/\(presets.count)")
                        .font(.system(.caption, design: .monospaced))
                        .opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .chipBackground()

                Spacer()

                if let err = capture.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        panelOpen.toggle()
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .chipBackground()
                .help("Effect settings (⌘,)")
            }

            Spacer()

            HStack {
                Text("← →  switch preset    ⌘,  settings")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .chipBackground()
                Spacer()
                if !capture.isRunning {
                    Button {
                        Task { await capture.start() }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
        }
        .padding(16)
        .opacity(overlayVisible || panelOpen ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: overlayVisible)
        .animation(.easeInOut(duration: 0.2), value: panelOpen)
        .allowsHitTesting(overlayVisible || panelOpen)
    }

    private func bumpOverlay() {
        overlayVisible = true
        hideOverlayTask?.cancel()
        hideOverlayTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled && !panelOpen { overlayVisible = false }
        }
    }

    private func installMouseMonitor() {
        removeMouseMonitor()
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged,
                       .rightMouseDown, .scrollWheel, .keyDown]
        ) { event in
            bumpOverlay()
            return event
        }
    }

    private func removeMouseMonitor() {
        if let m = mouseMonitor {
            NSEvent.removeMonitor(m)
            mouseMonitor = nil
        }
    }
}

/// Tiny wrapper so SwiftUI can own the analyzer via @StateObject.
final class AudioAnalyzer_Observable: ObservableObject {
    let analyzer = AudioAnalyzer()
}
