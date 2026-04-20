import Foundation
import SwiftUI
import simd

/// A single parameter's current value. Codable for persistence.
enum ParamValue: Equatable, Sendable {
    case float(Float)
    case int(Int)
    case bool(Bool)
    case color(SIMD4<Float>)   // rgba in sRGB 0..1
}

extension ParamValue: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "float":
            self = .float(try c.decode(Float.self, forKey: .value))
        case "int":
            self = .int(try c.decode(Int.self, forKey: .value))
        case "bool":
            self = .bool(try c.decode(Bool.self, forKey: .value))
        case "color":
            let arr = try c.decode([Float].self, forKey: .value)
            guard arr.count == 4 else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: c,
                                                       debugDescription: "color requires 4 floats")
            }
            self = .color(SIMD4<Float>(arr[0], arr[1], arr[2], arr[3]))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                                                   debugDescription: "unknown ParamValue type \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .float(let v):
            try c.encode("float", forKey: .type); try c.encode(v, forKey: .value)
        case .int(let v):
            try c.encode("int", forKey: .type); try c.encode(v, forKey: .value)
        case .bool(let v):
            try c.encode("bool", forKey: .type); try c.encode(v, forKey: .value)
        case .color(let v):
            try c.encode("color", forKey: .type); try c.encode([v.x, v.y, v.z, v.w], forKey: .value)
        }
    }
}

/// Where this parameter lives inside the Metal `PresetParams` buffer.
/// The renderer packs values into 16 float slots + 4 color slots.
enum ShaderSlot: Sendable {
    case float(Int)   // 0..<16
    case color(Int)   // 0..<4
}

/// A declarative description of one preset parameter.
struct ParamSpec: Identifiable, Sendable {
    enum Kind: Sendable {
        case slider(min: Float, max: Float)
        case stepper(min: Int, max: Int)
        case toggle
        case color
        case picker(options: [String])
    }

    let id: String            // unique within a preset
    let label: String
    let kind: Kind
    let defaultValue: ParamValue
    let slot: ShaderSlot
}

// MARK: - Value helpers

extension ParamValue {
    var asFloat: Float {
        switch self {
        case .float(let v): return v
        case .int(let v):   return Float(v)
        case .bool(let v):  return v ? 1.0 : 0.0
        case .color:        return 0
        }
    }

    var asColor: SIMD4<Float> {
        if case .color(let v) = self { return v }
        return .init(0, 0, 0, 1)
    }
}

extension Color {
    init(rgba: SIMD4<Float>) {
        self.init(.sRGB,
                  red: Double(rgba.x),
                  green: Double(rgba.y),
                  blue: Double(rgba.z),
                  opacity: Double(rgba.w))
    }

    func toRGBA() -> SIMD4<Float> {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return SIMD4<Float>(Float(ns.redComponent),
                            Float(ns.greenComponent),
                            Float(ns.blueComponent),
                            Float(ns.alphaComponent))
    }
}
