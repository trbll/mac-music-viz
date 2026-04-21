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

Four structs are shared across the language boundary. Their layout *must*
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

### `InteractionUniforms` (`buffer(2)`) — 48 bytes
```
offset 0   float2 mouse
offset 8   float2 previousMouse
offset 16  float2 velocity
offset 24  float2 dragStart
offset 32  float  isActive
offset 36  float  isDown
offset 40  float  clickPulse
offset 44  float  idleTime
```

Primary preset shaders can opt into this buffer for mouse-aware effects. It is
always bound, but old shaders can omit it from the signature.

### `PostUniforms` (`buffer(1)` in `fragment_post`) — 48-byte stride
```
offset 0   float2 resolution
offset 8   float  bloomIntensity
offset 12  float  bloomRadius
offset 16  float  bloomThreshold
offset 20  float  lensStrength
offset 24  float  rippleStrength
offset 28  float  chromaStrength
offset 32  float  vignette
offset 36  float  trailAmount
offset 40  float  trailDecay      // total 44 bytes, stride rounds to 48
```

`PostUniforms` is used by the post-processing shader, not by primary preset
shaders. If it changes, update `PostSettings.swift` and `Shaders.metal`
together.

`PostSettings` is keyed by `preset.id`, with preset-specific defaults and
stored overrides under `MusicViz.PostSettings.v2`. Mouse ripple/lens/chroma
are post settings too, so tune them per preset rather than as global values.

## Shader inputs reference

Every fragment shader gets the same plumbing. Knowing what's available keeps
you from reinventing it.

### `AudioUniforms` at `[[buffer(0)]]`
```metal
struct AudioUniforms {
    float  time;         // seconds since app start, monotonic, unbounded
    float  beat;         // 0..1, spikes on bass onset, decays ~0.88/frame
    float2 resolution;   // drawable pixel size
    float  bass;         // 0..1, smoothed (<200 Hz)
    float  mid;          // 0..1, smoothed (200 Hz..2 kHz)
    float  treble;       // 0..1, smoothed (>2 kHz)
    float  loudness;     // 0..1, smoothed RMS
};
```
All scalars are already smoothed and clamped. Don't re-smooth or re-clamp.

### `PresetParams` at `[[buffer(1)]]`
```metal
struct PresetParams {
    float4 p0, p1, p2, p3;   // your scalar slots (see packing below)
    float4 c0, c1, c2, c3;   // your color slots
};
```

### `InteractionUniforms` at `[[buffer(2)]]`
```metal
struct InteractionUniforms {
    float2 mouse;         // normalized 0..1, top-left origin
    float2 previousMouse; // previous mouse sample, normalized
    float2 velocity;      // smoothed normalized units/sec
    float2 dragStart;     // normalized click/drag start
    float  isActive;      // cursor inside, dragging, or recently moved
    float  isDown;        // mouse button down
    float  clickPulse;    // 1 on click, exponential decay
    float  idleTime;      // seconds since last pointer event
};
```
Only include this argument in shaders that use mouse input.

### Textures
```metal
texture2d<float> spectrum [[texture(0)]];   // 128 × 1, R32Float, log-spaced bins
texture2d<float> waveform [[texture(1)]];   // 256 × 1, R32Float, time-domain samples
```
Sample with:
```metal
constexpr sampler s(address::clamp_to_edge, filter::linear);
float mag = spectrum.sample(s, float2(uv.x, 0.5)).r;   // 0..~1 after window+norm
float wav = waveform.sample(s, float2(uv.x, 0.5)).r;   // -1..1-ish
```
Bind whichever textures you use — omit them from the signature if you don't.

### Render path
Primary presets render into an HDR `rgba16Float` scene texture. The shared
`fragment_post` shader then applies bloom, history trails, mouse ripple/lens,
chroma, and vignette into a second HDR texture. `fragment_copy` copies that
composited result into the drawable. Post and mouse effect intensities are
resolved per preset by `PostSettings`.

### Shared helpers in `Shaders.metal`
- `palette(float t)` — procedural IQ-style cyclic 3-channel palette. Use
  when you don't want to expose colors to the user.
- `palette2(t, c0, c1)` — 2-stop linear gradient.
- `palette3(t, c0, c1, c2)` — 3-stop linear palette.
- `palette4Lin(t, c0, c1, c2, c3)` — 4-stop linear palette.
- `palette4Cyc(t, c0, c1, c2, c3)` — 4-stop cyclic palette. `t` wraps.

Prefer the stop-based helpers with user-defined `PresetParams` colors over
the hardcoded `palette()` — that's how users tweak a preset's color scheme.

### Vertex shader
Don't write one. Use `vertex_fullscreen` — a big-triangle pass that hands the
fragment shader a `VOut` with `uv ∈ [0, 1]`, y-flipped so `uv.y = 0` is the
top of the screen (matches image-space intuition).

### UV conventions
- `in.uv` is `[0, 1]` screen-space, top-left origin.
- Centered coords: `float2 p = in.uv * 2.0 - 1.0;`
- Aspect-correct: `p.x *= u.resolution.x / u.resolution.y;`

## ParamSpec kinds — UI ↔ shader mapping

| `Kind`                     | SwiftUI control     | Persisted `ParamValue`       | Shader reads                    |
|----------------------------|---------------------|------------------------------|---------------------------------|
| `.slider(min, max)`        | `Slider`            | `.float(Float)`              | `p.p(k/4)[k%4]` (a float)       |
| `.stepper(min, max)`       | Quantized `Slider`  | `.int(Int)`                  | `p.p(k/4)[k%4]` (as float)      |
| `.toggle`                  | `Toggle`            | `.bool(Bool)`                | `step(0.5, p.p…)` → 0 or 1      |
| `.color`                   | `ColorPicker`       | `.color(SIMD4<Float>)`       | `p.c0/c1/c2/c3` (rgba)          |
| `.picker(options: […])`    | `Picker`            | `.int(Int)` (option idx)     | `p.p(k/4)[k%4]` (as float)      |
| `.palette(count: N)`       | Row of color wells  | `.palette([SIMD4<Float>])`   | `p.c<indices[0..N-1]>` (rgba×N) |

`k` is the `slot: .float(k)` index, `0..<16`. Color slots are `0..<4`. A
palette spec uses `slot: .palette([...])` — a list of color slot indices
(each `0..<4`). The first stop lands in the first listed slot, etc. Feed
them to `palette2/3/4Lin/palette4Cyc` to get user-controlled gradients.

## Adding a preset — worked example

Goal: a preset called "Rings" that draws concentric circles pulsing outward,
with configurable ring count, pulse speed, beat flash, and ring color.

### 1. Write the fragment shader

Append to `Shaders.metal`:

```metal
// ---------- 6. Rings ----------
// params: p0.x=ringCount, p0.y=pulseSpeed, p0.z=beatFlash, p0.w=thickness
// colors: c0..c2 = 3-stop palette indexed by radius
fragment float4 fragment_rings(VOut in [[stage_in]],
                               constant AudioUniforms& u [[buffer(0)]],
                               constant PresetParams& p [[buffer(1)]]) {
    float ringCount  = max(1.0, p.p0.x);
    float pulseSpeed = p.p0.y;
    float beatFlash  = p.p0.z;
    float thickness  = max(0.01, p.p0.w);

    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 uv = in.uv * 2.0 - 1.0;
    uv.x *= aspect;

    float r = length(uv);
    float phase = u.time * pulseSpeed + u.bass * 2.0;

    // distance to nearest ring edge
    float rings = fract(r * ringCount - phase);
    float edge  = smoothstep(thickness, 0.0, abs(rings - 0.5));

    float3 col = palette3(clamp(r, 0.0, 1.0), p.c0.rgb, p.c1.rgb, p.c2.rgb) * edge;
    col *= 1.0 + u.beat * beatFlash;
    col *= smoothstep(1.6, 0.2, r);   // radial falloff
    return float4(col, 1.0);
}
```

### 2. Register the preset

Edit `PresetManager.swift`. Add a new file-scope constant below the others:

```swift
private let rings = Preset(
    id: "rings", name: "Rings", fragmentFunction: "fragment_rings",
    params: [
        .init(id: "ringCount",  label: "Ring count",  kind: .stepper(min: 2, max: 40),
              defaultValue: .int(12),   slot: .float(0)),
        .init(id: "pulseSpeed", label: "Pulse speed", kind: .slider(min: 0, max: 4),
              defaultValue: .float(1.0), slot: .float(1)),
        .init(id: "beatFlash",  label: "Beat flash",  kind: .slider(min: 0, max: 3),
              defaultValue: .float(1.2), slot: .float(2)),
        .init(id: "thickness",  label: "Thickness",   kind: .slider(min: 0.05, max: 0.8),
              defaultValue: .float(0.25), slot: .float(3)),
        .init(id: "palette",    label: "Palette",     kind: .palette(count: 3),
              defaultValue: .palette([
                  .init(0.9, 0.6, 1.0, 1.0),
                  .init(0.4, 0.8, 1.0, 1.0),
                  .init(1.0, 0.9, 0.5, 1.0),
              ]),
              slot: .palette([0, 1, 2])),
    ]
)
```

Then add it to `all`:
```swift
static let all: [Preset] = [plasma, tunnel, bars, oscilloscope, bloom, rings]
```

### 3. Build and run

```bash
cd MusicViz && xcodebuild -project MusicViz.xcodeproj -scheme MusicViz \
    -configuration Debug build | grep -E "(error:|BUILD (SUCCEEDED|FAILED))"
```

If it builds, ⌘R in Xcode, press `→` until you cycle to Rings, ⌘, to tweak.

### Rules and gotchas

- **`id` is a stable key.** Once shipped, don't rename — user's saved
  settings are keyed on it. Same for each `ParamSpec.id` within the preset.
- **Slot collisions within a preset silently overwrite.** If two `ParamSpec`s
  in the same preset declare `slot: .float(0)`, whichever is packed last
  wins. `ParamStore.packed` iterates in order.
- **Slot collisions across presets are fine** — each preset has its own
  `PresetParams` packed fresh every frame.
- **Don't reuse a `ParamSpec.id` across presets unless intentional** — the
  store is scoped per-preset (`values[presetId][key]`), so it's safe, but it
  can confuse readers. Prefer distinct names.
- **Bools and ints land in float slots.** In shader, bool → use
  `step(0.5, p.p0.z)`; int → just use it as a float and round if needed.
- **Missing `fragmentFunction` → renderer logs and draws nothing.** Check
  the function name matches the MSL exactly (case-sensitive).
- **Shader compile errors fail the pipeline build.** Look for
  `MusicViz: pipeline build failed for <id>: …` in the Xcode console.
  Metal reports line numbers relative to `Shaders.metal`.
- **Every preset auto-gets spectrum + waveform textures bound.** They're
  only used if your fragment function takes them as `[[texture(0/1)]]`
  params; otherwise the binding is a no-op.

## Adding a new `ParamSpec.Kind`

Rare, but if you need (say) a two-float vector picker or a file path:

1. Extend `ParamSpec.Kind` with the new case.
2. Extend `ParamValue` with a new case + Codable encode/decode branches.
3. Extend `ParamValue.asFloat` / `asColor` (or add a new accessor) so
   `ParamStore.packed` can read it.
4. Add a branch in `ConfigPanel.ParamRow.control` rendering the new SwiftUI
   control bound to a `ParamValue`-round-tripping `Binding`.
5. Document the shader side here (which slot type it lands in, how the
   shader should read it).

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
