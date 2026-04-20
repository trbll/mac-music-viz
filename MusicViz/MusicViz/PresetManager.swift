import Foundation
import simd

struct Preset: Identifiable, Sendable {
    let id: String
    let name: String
    let fragmentFunction: String
    let params: [ParamSpec]
}

final class PresetManager: ObservableObject {
    static let all: [Preset] = [plasma, tunnel, bars, oscilloscope, bloom]

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
