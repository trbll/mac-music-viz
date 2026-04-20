# MusicViz

A system-level music visualizer for macOS. Captures whatever audio your Mac is
playing — Apple Music, Spotify, YouTube, anything — and renders it through a
set of Metal shader presets.

![plasma, tunnel, spectrum bars, oscilloscope, bloom — five built-in presets](docs/preview.png)

## Requirements

- **macOS 14.0** (Sonoma) or newer
- **Xcode 16.x** to build
- Screen Recording permission (macOS uses this to route system audio to the app
  via ScreenCaptureKit — no virtual audio driver required)

## Setup

1. Open `MusicViz/MusicViz.xcodeproj` in Xcode.
2. Build and run (⌘R). First launch will fail silently to capture audio — macOS
   will prompt for **Screen Recording** permission.
3. Grant it in **System Settings → Privacy & Security → Screen Recording**,
   then **quit and relaunch** the app. macOS requires a fresh process to pick
   up the permission.
4. Start playing audio in any app. The visualizer picks it up automatically.

## Controls

| Key / gesture | Action                                              |
|---------------|-----------------------------------------------------|
| `←` / `→`     | Previous / next preset                              |
| `space`       | Next preset                                         |
| `⌘,`          | Toggle effect settings panel                        |
| gear icon     | Toggle effect settings panel                        |
| mouse move    | Wake overlay (auto-hides after 2.5s of no activity) |

The settings panel has per-preset sliders, toggles, and color pickers. Every
tweak auto-saves to `UserDefaults` under the key `MusicViz.ParamStore.v1`. Per
parameter you can reset to default (↺ icon); you can also reset all parameters
for the current preset from the bottom button.

## Presets

| Name           | Fragment shader         | Vibe                                   |
|----------------|-------------------------|----------------------------------------|
| Plasma         | `fragment_plasma`       | Flowing color field, palette-based     |
| Tunnel         | `fragment_tunnel`       | Depth rings + spokes, beat-punched     |
| Spectrum Bars  | `fragment_bars`         | Classic log-spaced spectrum bars       |
| Oscilloscope   | `fragment_oscilloscope` | CRT-style waveform trace with scanlines|
| Apple Bloom    | `fragment_bloom`        | Soft drifting blobs, Apple-Music-ish   |

## Architecture

```
┌─────────────────────┐    audio samples   ┌──────────────────┐
│ AudioCaptureService │ ─────────────────▶ │  AudioAnalyzer   │
│  (ScreenCaptureKit) │                    │  (vDSP FFT)      │
└─────────────────────┘                    └──────────────────┘
                                                    │
                                          snapshot  │ each frame
                                                    ▼
                   ┌─────────────┐          ┌──────────────────┐
                   │ PresetManager│         │  MetalRenderer   │
                   │  ParamStore  │────────▶│  (MTKView)       │
                   └─────────────┘  params  └──────────────────┘
                                                    │
                                                    ▼
                                             Fragment shader
                                             (Shaders.metal)
```

- **AudioCaptureService** uses ScreenCaptureKit's `SCStream` with
  `capturesAudio = true` to pull system audio without a virtual driver. Samples
  are mixed to mono and pushed to the analyzer.
- **AudioAnalyzer** keeps a ring buffer, runs a 2048-point Hann-windowed FFT
  via `vDSP_fft_zrip` at up to 90 Hz, and exposes a thread-safe `AudioState`
  snapshot (bass/mid/treble energies, RMS loudness, beat onset, 128-bin
  log-spaced spectrum, 256-sample waveform).
- **MetalRenderer** owns one `MTLRenderPipelineState` per preset (cached on
  first use), uploads the spectrum and waveform to 1D R32Float textures, and
  passes `AudioUniforms` + `PresetParams` buffers to the fragment shader.
- **PresetManager** declares the preset list and each preset's `ParamSpec[]`
  (float slider / int stepper / bool toggle / color picker / enum picker).
- **ParamStore** persists per-preset values to UserDefaults and packs them
  into the GPU-ready `PresetParams` struct each frame.

## Extending

See [CLAUDE.md](CLAUDE.md) for:

- [Shader inputs reference](CLAUDE.md#shader-inputs-reference) — what's bound
  in every fragment shader (audio uniforms, textures, helpers)
- [ParamSpec kinds](CLAUDE.md#paramspec-kinds--ui--shader-mapping) — the
  UI-to-shader mapping for each control type
- [Adding a preset — worked example](CLAUDE.md#adding-a-preset--worked-example)
  — end-to-end: fragment function, registration, running it
- [Adding a new `ParamSpec.Kind`](CLAUDE.md#adding-a-new-paramspeckind) — when
  the built-in control types aren't enough

## Project layout

```
music-viz/
├── README.md
├── CLAUDE.md
└── MusicViz/
    ├── MusicViz.xcodeproj
    └── MusicViz/
        ├── MusicVizApp.swift          — @main app entry
        ├── ContentView.swift          — root view, overlay, panel toggle
        ├── AudioCaptureService.swift  — ScreenCaptureKit audio capture
        ├── AudioAnalyzer.swift        — FFT + band energies + beat detect
        ├── MetalView.swift            — SwiftUI wrapper for MTKView
        ├── MetalRenderer.swift        — per-frame draw + uniform packing
        ├── PresetManager.swift        — preset list + per-preset ParamSpec
        ├── ParamSpec.swift            — param types + Codable + ShaderSlot
        ├── ParamStore.swift           — persistence + packed() for shader
        ├── ConfigPanel.swift          — settings overlay UI
        ├── GlassEffects.swift         — translucent panel/chip modifiers
        └── Shaders.metal              — vertex_fullscreen + fragment_*
```

## Roadmap

- [ ] Upgrade `GlassEffects.swift` to real Liquid Glass (`.glassEffect(...)`)
      once on Xcode 26 / macOS 26
- [ ] More presets (particles, fluid sim, CRT raymarch)
- [ ] Fullscreen on dedicated display from menu
- [ ] Preset export / import as JSON
- [ ] Per-preset color palette picker (multiple colors, not just tint)
