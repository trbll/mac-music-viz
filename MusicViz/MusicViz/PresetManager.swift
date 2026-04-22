import Foundation
import simd

struct Preset: Identifiable, Sendable {
    let id: String
    let name: String
    let fragmentFunction: String
    let params: [ParamSpec]
}

final class PresetManager: ObservableObject {
    static let all: [Preset] = [
        plasma,
        tunnel,
        bars,
        oscilloscope,
        bloom,
        chladni,
        aurora,
        kaleidoscope,
        topographic,
        constellation,
        vinyl,
        imageReactor
    ]

    @Published private(set) var index: Int = 0
    var current: Preset { Self.all[index] }
    var count: Int { Self.all.count }

    func next() { index = (index + 1) % count }
    func prev() { index = (index - 1 + count) % count }
    func select(id: String) {
        if let i = Self.all.firstIndex(where: { $0.id == id }) { index = i }
    }
}

// MARK: - Preset definitions

private let plasma = Preset(
    id: "plasma", name: "Plasma", fragmentFunction: "fragment_plasma",
    params: [
        .init(id: "scale",      label: "Scale",      kind: .slider(min: 1, max: 8),
              defaultValue: .float(4.0), slot: .float(0)),
        .init(id: "speed",      label: "Speed",      kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.3), slot: .float(1)),
        .init(id: "bassReact",  label: "Bass react", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.4), slot: .float(2)),
        .init(id: "brightness", label: "Brightness", kind: .slider(min: 0, max: 2),
              defaultValue: .float(1.0), slot: .float(3)),
        .init(id: "palette",    label: "Palette",    kind: .palette(count: 4),
              defaultValue: .palette([
                  .init(1.00, 0.26, 0.26, 1.0),
                  .init(0.50, 0.06, 0.94, 1.0),
                  .init(0.00, 0.74, 0.74, 1.0),
                  .init(0.50, 0.94, 0.06, 1.0),
              ]),
              slot: .palette([0, 1, 2, 3])),
    ]
)

private let tunnel = Preset(
    id: "tunnel", name: "Tunnel", fragmentFunction: "fragment_tunnel",
    params: [
        .init(id: "ringSpeed", label: "Ring speed", kind: .slider(min: 0, max: 6),
              defaultValue: .float(3.0), slot: .float(0)),
        .init(id: "spokes",    label: "Spokes",     kind: .stepper(min: 2, max: 24),
              defaultValue: .int(10), slot: .float(1)),
        .init(id: "beatPunch", label: "Beat punch", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.8), slot: .float(2)),
        .init(id: "bassReact", label: "Bass react", kind: .slider(min: 0, max: 2),
              defaultValue: .float(1.0), slot: .float(3)),
        .init(id: "palette",   label: "Palette",    kind: .palette(count: 4),
              defaultValue: .palette([
                  .init(0.10, 0.20, 0.50, 1.0),
                  .init(0.40, 0.10, 0.80, 1.0),
                  .init(0.20, 0.70, 0.90, 1.0),
                  .init(0.90, 0.30, 0.70, 1.0),
              ]),
              slot: .palette([0, 1, 2, 3])),
    ]
)

private let bars = Preset(
    id: "bars", name: "Spectrum Bars", fragmentFunction: "fragment_bars",
    params: [
        .init(id: "gain",    label: "Gain",       kind: .slider(min: 0.5, max: 6),
              defaultValue: .float(3.2), slot: .float(0)),
        .init(id: "peak",    label: "Peak glow",  kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.8), slot: .float(1)),
        .init(id: "floor",   label: "Floor glow", kind: .slider(min: 0, max: 2),
              defaultValue: .float(1.0), slot: .float(2)),
        .init(id: "palette", label: "Palette",    kind: .palette(count: 3),
              defaultValue: .palette([
                  .init(0.20, 0.80, 1.00, 1.0),   // low-freq (left)
                  .init(0.60, 1.00, 0.20, 1.0),   // mid
                  .init(1.00, 0.40, 0.20, 1.0),   // high-freq (right)
              ]),
              slot: .palette([0, 1, 2])),
    ]
)

private let oscilloscope = Preset(
    id: "oscilloscope", name: "Oscilloscope", fragmentFunction: "fragment_oscilloscope",
    params: [
        .init(id: "thickness", label: "Thickness", kind: .slider(min: 0.3, max: 3),
              defaultValue: .float(1.0), slot: .float(0)),
        .init(id: "glow",      label: "Glow",      kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.35), slot: .float(1)),
        .init(id: "scanlines", label: "Scanlines", kind: .toggle,
              defaultValue: .bool(true), slot: .float(2)),
        .init(id: "grid",      label: "Grid",      kind: .toggle,
              defaultValue: .bool(true), slot: .float(3)),
        .init(id: "palette",   label: "Trace / glow", kind: .palette(count: 2),
              defaultValue: .palette([
                  .init(0.15, 1.00, 0.40, 1.0),   // trace
                  .init(0.05, 0.40, 0.15, 1.0),   // glow / grid
              ]),
              slot: .palette([0, 1])),
    ]
)

private let bloom = Preset(
    id: "bloom", name: "Apple Bloom", fragmentFunction: "fragment_bloom",
    params: [
        .init(id: "blobs",     label: "Blob count", kind: .stepper(min: 2, max: 8),
              defaultValue: .int(5), slot: .float(0)),
        .init(id: "speed",     label: "Speed",      kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.18), slot: .float(1)),
        .init(id: "bassReact", label: "Bass react", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.18), slot: .float(2)),
        .init(id: "gamma",     label: "Gamma",      kind: .slider(min: 0.5, max: 2),
              defaultValue: .float(0.85), slot: .float(3)),
        .init(id: "palette",   label: "Palette",    kind: .palette(count: 4),
              defaultValue: .palette([
                  .init(1.00, 0.60, 0.80, 1.0),
                  .init(0.70, 0.50, 1.00, 1.0),
                  .init(0.40, 0.90, 1.00, 1.0),
                  .init(0.90, 0.90, 0.60, 1.0),
              ]),
              slot: .palette([0, 1, 2, 3])),
    ]
)

private let chladni = Preset(
    id: "chladni", name: "Chladni Plate", fragmentFunction: "fragment_chladni",
    params: [
        .init(id: "modeX", label: "Mode X", kind: .stepper(min: 2, max: 18),
              defaultValue: .int(5), slot: .float(0)),
        .init(id: "modeY", label: "Mode Y", kind: .stepper(min: 2, max: 18),
              defaultValue: .int(7), slot: .float(1)),
        .init(id: "lineSharpness", label: "Line sharpness", kind: .slider(min: 8, max: 70),
              defaultValue: .float(34.0), slot: .float(2)),
        .init(id: "beatFlash", label: "Beat flash", kind: .slider(min: 0, max: 3),
              defaultValue: .float(1.15), slot: .float(3)),
        .init(id: "drift", label: "Drift", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.35), slot: .float(4)),
        .init(id: "scale", label: "Scale", kind: .slider(min: 0.5, max: 4),
              defaultValue: .float(1.18), slot: .float(5)),
        .init(id: "palette", label: "Palette", kind: .palette(count: 3),
              defaultValue: .palette([
                  .init(0.04, 0.02, 0.08, 1.0),
                  .init(0.12, 0.85, 1.00, 1.0),
                  .init(1.00, 0.82, 0.28, 1.0),
              ]),
              slot: .palette([0, 1, 2])),
    ]
)

private let aurora = Preset(
    id: "aurora", name: "Aurora Ribbon", fragmentFunction: "fragment_aurora",
    params: [
        .init(id: "layers", label: "Layers", kind: .stepper(min: 2, max: 9),
              defaultValue: .int(5), slot: .float(0)),
        .init(id: "flowSpeed", label: "Flow speed", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.28), slot: .float(1)),
        .init(id: "gain", label: "Gain", kind: .slider(min: 0.5, max: 5),
              defaultValue: .float(2.4), slot: .float(2)),
        .init(id: "shimmer", label: "Shimmer", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.75), slot: .float(3)),
        .init(id: "haze", label: "Haze", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.55), slot: .float(4)),
        .init(id: "palette", label: "Palette", kind: .palette(count: 4),
              defaultValue: .palette([
                  .init(0.04, 0.12, 0.18, 1.0),
                  .init(0.12, 0.92, 0.64, 1.0),
                  .init(0.38, 0.40, 1.00, 1.0),
                  .init(1.00, 0.36, 0.70, 1.0),
              ]),
              slot: .palette([0, 1, 2, 3])),
    ]
)

private let kaleidoscope = Preset(
    id: "kaleidoscope", name: "Kaleidoscope Prism", fragmentFunction: "fragment_kaleidoscope",
    params: [
        .init(id: "segments", label: "Segments", kind: .stepper(min: 3, max: 18),
              defaultValue: .int(8), slot: .float(0)),
        .init(id: "rotation", label: "Rotation", kind: .slider(min: 0, max: 3),
              defaultValue: .float(0.35), slot: .float(1)),
        .init(id: "warp", label: "Warp", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.75), slot: .float(2)),
        .init(id: "beatPunch", label: "Beat punch", kind: .slider(min: 0, max: 3),
              defaultValue: .float(1.2), slot: .float(3)),
        .init(id: "prism", label: "Prism", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.8), slot: .float(4)),
        .init(id: "palette", label: "Palette", kind: .palette(count: 4),
              defaultValue: .palette([
                  .init(1.00, 0.18, 0.42, 1.0),
                  .init(1.00, 0.82, 0.20, 1.0),
                  .init(0.15, 0.90, 1.00, 1.0),
                  .init(0.55, 0.25, 1.00, 1.0),
              ]),
              slot: .palette([0, 1, 2, 3])),
    ]
)

private let topographic = Preset(
    id: "topographic", name: "Topographic Pulse", fragmentFunction: "fragment_topographic",
    params: [
        .init(id: "contours", label: "Contours", kind: .stepper(min: 6, max: 36),
              defaultValue: .int(18), slot: .float(0)),
        .init(id: "terrainScale", label: "Terrain scale", kind: .slider(min: 1, max: 8),
              defaultValue: .float(3.4), slot: .float(1)),
        .init(id: "drift", label: "Drift", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.22), slot: .float(2)),
        .init(id: "shockwave", label: "Shockwave", kind: .slider(min: 0, max: 3),
              defaultValue: .float(1.2), slot: .float(3)),
        .init(id: "lineWidth", label: "Line width", kind: .slider(min: 0.1, max: 2),
              defaultValue: .float(0.75), slot: .float(4)),
        .init(id: "palette", label: "Palette", kind: .palette(count: 4),
              defaultValue: .palette([
                  .init(0.03, 0.05, 0.06, 1.0),
                  .init(0.10, 0.48, 0.72, 1.0),
                  .init(0.42, 0.76, 0.36, 1.0),
                  .init(1.00, 0.92, 0.65, 1.0),
              ]),
              slot: .palette([0, 1, 2, 3])),
    ]
)

private let constellation = Preset(
    id: "constellation", name: "Spectral Constellation", fragmentFunction: "fragment_constellation",
    params: [
        .init(id: "density", label: "Density", kind: .stepper(min: 16, max: 96),
              defaultValue: .int(56), slot: .float(0)),
        .init(id: "spiral", label: "Spiral", kind: .slider(min: 0, max: 4),
              defaultValue: .float(1.25), slot: .float(1)),
        .init(id: "connectionGlow", label: "Connection glow", kind: .slider(min: 0, max: 3),
              defaultValue: .float(1.0), slot: .float(2)),
        .init(id: "speed", label: "Speed", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.22), slot: .float(3)),
        .init(id: "sparkle", label: "Sparkle", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.9), slot: .float(4)),
        .init(id: "palette", label: "Palette", kind: .palette(count: 3),
              defaultValue: .palette([
                  .init(1.00, 0.76, 0.28, 1.0),
                  .init(0.28, 0.86, 1.00, 1.0),
                  .init(1.00, 0.38, 0.78, 1.0),
              ]),
              slot: .palette([0, 1, 2])),
    ]
)

private let vinyl = Preset(
    id: "vinyl", name: "Vinyl Scanner", fragmentFunction: "fragment_vinyl",
    params: [
        .init(id: "grooves", label: "Grooves", kind: .stepper(min: 24, max: 120),
              defaultValue: .int(72), slot: .float(0)),
        .init(id: "scanSpeed", label: "Scan speed", kind: .slider(min: 0, max: 3),
              defaultValue: .float(0.45), slot: .float(1)),
        .init(id: "wobble", label: "Wobble", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.85), slot: .float(2)),
        .init(id: "notchGain", label: "Notch gain", kind: .slider(min: 0.5, max: 5),
              defaultValue: .float(2.5), slot: .float(3)),
        .init(id: "labelGlow", label: "Label glow", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.45), slot: .float(4)),
        .init(id: "palette", label: "Palette", kind: .palette(count: 3),
              defaultValue: .palette([
                  .init(0.015, 0.015, 0.018, 1.0),
                  .init(0.86, 0.82, 0.70, 1.0),
                  .init(1.00, 0.24, 0.16, 1.0),
              ]),
              slot: .palette([0, 1, 2])),
    ]
)

private let imageReactor = Preset(
    id: "imageReactor", name: "Image Reactor", fragmentFunction: "fragment_image_reactor",
    params: [
        .init(id: "mode", label: "Mode",
              kind: .picker(options: ["Liquid", "Pulse", "Chroma", "Glitch", "Mirror", "Wave", "Smear", "Shock"]),
              defaultValue: .int(0), slot: .float(0)),
        .init(id: "intensity", label: "Intensity", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.95), slot: .float(1)),
        .init(id: "speed", label: "Speed", kind: .slider(min: 0, max: 3),
              defaultValue: .float(0.72), slot: .float(2)),
        .init(id: "scale", label: "Scale", kind: .slider(min: 0.5, max: 2.5),
              defaultValue: .float(1.0), slot: .float(3)),
        .init(id: "segments", label: "Segments", kind: .stepper(min: 3, max: 24),
              defaultValue: .int(9), slot: .float(4)),
        .init(id: "displace", label: "Displace", kind: .slider(min: 0, max: 1.5),
              defaultValue: .float(0.70), slot: .float(5)),
        .init(id: "colorBoost", label: "Color boost", kind: .slider(min: 0, max: 2),
              defaultValue: .float(0.55), slot: .float(6)),
        .init(id: "detail", label: "Detail", kind: .slider(min: 0, max: 1),
              defaultValue: .float(0.35), slot: .float(7)),
        .init(id: "margin", label: "Margin", kind: .slider(min: 0, max: 0.20),
              defaultValue: .float(0.04), slot: .float(8)),
        .init(id: "reactiveTint", label: "Reactive tint", kind: .palette(count: 3),
              defaultValue: .palette([
                  .init(0.06, 0.18, 0.28, 1.0),
                  .init(0.22, 0.85, 1.00, 1.0),
                  .init(1.00, 0.32, 0.54, 1.0),
              ]),
              slot: .palette([0, 1, 2])),
    ]
)
