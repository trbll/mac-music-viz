# CLAUDE.md

Project-specific notes for Claude Code. The public-facing overview is in
[README.md](README.md); this file covers conventions and pitfalls that
matter when editing the code.

## Tech stack

- SwiftUI macOS app, deployment target **macOS 14.0**
- Metal via `MTKView` + MSL fragment shaders
- Accelerate (vDSP) for FFT
- ScreenCaptureKit for system-audio capture (no virtual audio driver)

Xcode project lives at `MusicViz/MusicViz.xcodeproj`. All Swift and Metal
sources live in `MusicViz/MusicViz/`.

## Build commands

```bash
# Build (from repo root)
cd MusicViz && xcodebuild -project MusicViz.xcodeproj -scheme MusicViz \
    -configuration Debug -destination 'platform=macOS' build

# Filtered output
... | grep -E "(error:|warning:|BUILD (SUCCEEDED|FAILED))"
```

**Always run `xcodebuild` before handing back to the user.** Don't rely on
"this should compile" — Xcode's errors panel sometimes lags, and running the
build surfaces typos, Swift-concurrency warnings, Metal pipeline mismatches
in seconds.

## Uniform layout contract (Swift ↔ MSL)

Two structs are shared across the language boundary. Their layout *must*
match byte-for-byte. If you change either side, change both.

### `AudioUniforms` (`buffer(0)`)
```
offset 0   float  time
offset 4   float  beat
offset 8   float2 resolution
offset 16  float  bass
offset 20  float  mid
offset 24  float  treble
offset 28  float  loudness     // total 32 bytes
```

### `PresetParams` (`buffer(1)`) — 128 bytes
```
offset 0    float4 p0           // scalar slots  0..3
offset 16   float4 p1           // scalar slots  4..7
offset 32   float4 p2           // scalar slots  8..11
offset 48   float4 p3           // scalar slots 12..15
offset 64   float4 c0           // color slot 0
offset 80   float4 c1           // color slot 1
offset 96   float4 c2           // color slot 2
offset 112  float4 c3           // color slot 3
```

`ParamSpec.slot` is either `.float(i)` where `i ∈ 0..<16` (mapped to
`p(i/4).(x|y|z|w)` by `ParamStore.packed`) or `.color(i)` where `i ∈ 0..<4`
(mapped to `c0..c3`). Bools pack as `0.0`/`1.0` floats; ints cast to float.

## Adding a preset

1. Add a fragment function in `Shaders.metal`:
   ```metal
   fragment float4 fragment_new(VOut in [[stage_in]],
                                constant AudioUniforms& u [[buffer(0)]],
                                constant PresetParams& p [[buffer(1)]]) {
       // read params: float x = p.p0.x; float3 tint = p.c0.rgb;
       return float4(...);
   }
   ```
2. Add a `Preset` entry in `PresetManager.all` with:
   - unique `id` (used as the UserDefaults key prefix)
   - `fragmentFunction` matching the MSL function name
   - a `[ParamSpec]` list declaring which slots it reads and the control type
3. Build. The renderer compiles and caches the pipeline on first use.

Do **not** reuse the same `id` across presets — it will collide in
`ParamStore`'s persistence dictionary.

## ScreenCaptureKit gotchas

- Requires a bundled app with a valid `Info.plist`. Running via
  `swift run` won't work — only Xcode-built `.app` bundles get screen
  recording permission.
- **App Sandbox must be OFF** for non-App-Store builds. Re-enabling it
  requires adding specific entitlements that Apple doesn't fully document
  for SCK — easier to leave it off.
- First run will prompt for Screen Recording permission. After granting,
  **the app must be relaunched** — macOS doesn't apply the permission to
  the running process.
- `SCStream` with `capturesAudio = true` still requires a filter (display or
  window), and we must add a `.screen` stream output (even though we ignore
  its samples) or the stream fails to start on some macOS versions. The
  video stream is configured at 2×2 at 8 fps to minimize GPU/CPU cost.
- `excludesCurrentProcessAudio = true` prevents the visualizer from feeding
  back on its own output (if it ever gets one).

## Threading model

- `AudioCaptureService` is a plain NSObject. Its `SCStreamOutput` callbacks
  fire on `MusicViz.SCStream.audio` (user-interactive dispatch queue).
- `AudioAnalyzer` is `@unchecked Sendable`. Ring buffer and state struct
  are both protected by NSLocks. `push` is called from the audio queue;
  `snapshot` is called from the main/render thread.
- `MTKView.delegate.draw(in:)` runs on the main thread by default. The
  renderer reads an `AudioState` snapshot each frame — cheap copy.
- Don't introduce `@Published` on the audio hot path. UI state
  (`capture.isRunning`, `presets.index`, `params.values`) is the only
  place `@Published` is appropriate, and changes there flow through
  `MainActor.run` / main queue.

## Liquid Glass (future)

`GlassEffects.swift` currently uses `.ultraThinMaterial` because the
Liquid Glass APIs (`Glass`, `.glassEffect(_:in:)`, `GlassEffectContainer`)
require the macOS 26 SDK, which ships with Xcode 26. When this project
migrates to Xcode 26 and the deployment target bumps (or stays at 14 with
`@available(macOS 26.0, *)` branches), swap the implementations:

```swift
@available(macOS 26.0, *)
extension View {
    func panelBackground<S: Shape>(_ shape: S) -> some View {
        self.glassEffect(.regular.tint(nil).interactive(false), in: shape)
    }
}
```

Keep the `.ultraThinMaterial` path as the pre-26 fallback inside an
`#available` branch. Do **not** import or reference `Glass` at top level
in the current Xcode 16 SDK — the symbol doesn't exist and it won't
compile even behind `@available`.

## Known quirks

- **Stale Previews stub window**: if a "Hello, world!" window appears
  alongside the real app, that's Xcode's Previews helper process running
  an old snapshot. Clean build folder (⇧⌘K) + quit/relaunch Xcode clears
  it. It has nothing to do with the running app.
- **`device.makeDefaultLibrary()` crashes**: means `Shaders.metal` isn't
  in the Xcode target. Right-click MusicViz group → Add Files → check
  "Add to targets: MusicViz".
- **First-run blank window**: likely Screen Recording permission pending.
  Check System Settings and relaunch.

## Style

- No comments explaining *what* code does — identifiers should make that
  clear. Reserve comments for *why*: a non-obvious constraint, a layout
  contract (like the MSL/Swift match above), or an OS quirk.
- Prefer typed params (`ParamValue` enum) over stringly-typed dictionaries.
- Shader magic numbers are fine inline — the preset is the spec.
