import Foundation
import simd

struct InteractionUniforms {
    var mouse: SIMD2<Float> = .init(0.5, 0.5)
    var previousMouse: SIMD2<Float> = .init(0.5, 0.5)
    var velocity: SIMD2<Float> = .zero
    var dragStart: SIMD2<Float> = .init(0.5, 0.5)
    var isActive: Float = 0
    var isDown: Float = 0
    var clickPulse: Float = 0
    var idleTime: Float = 0
}

struct PostUniforms {
    var resolution: SIMD2<Float> = .zero
    var bloomIntensity: Float = 0
    var bloomRadius: Float = 1
    var bloomThreshold: Float = 0.62
    var lensStrength: Float = 0
    var rippleStrength: Float = 0
    var chromaStrength: Float = 0
    var vignette: Float = 0
    var trailAmount: Float = 0
    var trailDecay: Float = 0.88
}

enum PostSetting: String, CaseIterable, Sendable {
    case bloom
    case trails
    case mouseRipple
    case mouseLens
    case chroma
    case vignette

    var label: String {
        switch self {
        case .bloom: return "Bloom"
        case .trails: return "Trails"
        case .mouseRipple: return "Mouse ripple"
        case .mouseLens: return "Mouse lens"
        case .chroma: return "Chroma"
        case .vignette: return "Vignette"
        }
    }

    var range: ClosedRange<Float> {
        switch self {
        case .bloom: return 0...1.6
        case .trails: return 0...0.8
        case .mouseRipple: return 0...0.3
        case .mouseLens: return 0...0.35
        case .chroma: return 0...0.6
        case .vignette: return 0...0.8
        }
    }
}

struct PostValues: Codable, Equatable, Sendable {
    var bloom: Float
    var trails: Float
    var mouseRipple: Float
    var mouseLens: Float
    var chroma: Float
    var vignette: Float

    subscript(setting: PostSetting) -> Float {
        get {
            switch setting {
            case .bloom: return bloom
            case .trails: return trails
            case .mouseRipple: return mouseRipple
            case .mouseLens: return mouseLens
            case .chroma: return chroma
            case .vignette: return vignette
            }
        }
        set {
            switch setting {
            case .bloom: bloom = newValue
            case .trails: trails = newValue
            case .mouseRipple: mouseRipple = newValue
            case .mouseLens: mouseLens = newValue
            case .chroma: chroma = newValue
            case .vignette: vignette = newValue
            }
        }
    }
}

final class PostSettings: ObservableObject {
    @Published private var values: [String: PostValues] = [:]

    private let defaultsKey = "MusicViz.PostSettings.v2"

    init() {
        load()
    }

    func value(presetId: String, setting: PostSetting) -> Float {
        resolvedValues(for: presetId)[setting]
    }

    func set(_ value: Float, presetId: String, setting: PostSetting) {
        var presetValues = resolvedValues(for: presetId)
        presetValues[setting] = min(max(value, setting.range.lowerBound), setting.range.upperBound)
        values[presetId] = presetValues
        save()
    }

    func reset(presetId: String) {
        values.removeValue(forKey: presetId)
        save()
    }

    func uniforms(for presetId: String, resolution: SIMD2<Float>, historyReady: Bool) -> PostUniforms {
        let v = resolvedValues(for: presetId)
        return PostUniforms(
            resolution: resolution,
            bloomIntensity: v.bloom,
            bloomRadius: 1.25,
            bloomThreshold: 0.60,
            lensStrength: v.mouseLens,
            rippleStrength: v.mouseRipple,
            chromaStrength: v.chroma,
            vignette: v.vignette,
            trailAmount: historyReady ? v.trails : 0,
            trailDecay: 0.88
        )
    }

    private func resolvedValues(for presetId: String) -> PostValues {
        values[presetId] ?? Defaults.values(for: presetId)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        do {
            values = try JSONDecoder().decode([String: PostValues].self, from: data)
        } catch {
            NSLog("MusicViz: failed to load post settings: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(values)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            NSLog("MusicViz: failed to save post settings: \(error)")
        }
    }
}

private enum Defaults {
    static func values(for presetId: String) -> PostValues {
        switch presetId {
        case "oscilloscope":
            return .init(bloom: 0.24, trails: 0.03, mouseRipple: 0.03,
                         mouseLens: 0.04, chroma: 0.10, vignette: 0.26)
        case "bars":
            return .init(bloom: 0.42, trails: 0.08, mouseRipple: 0.05,
                         mouseLens: 0.06, chroma: 0.12, vignette: 0.18)
        case "plasma":
            return .init(bloom: 0.52, trails: 0.12, mouseRipple: 0.08,
                         mouseLens: 0.10, chroma: 0.18, vignette: 0.20)
        case "tunnel":
            return .init(bloom: 0.72, trails: 0.18, mouseRipple: 0.10,
                         mouseLens: 0.12, chroma: 0.24, vignette: 0.28)
        case "bloom":
            return .init(bloom: 0.38, trails: 0.12, mouseRipple: 0.07,
                         mouseLens: 0.09, chroma: 0.12, vignette: 0.12)
        case "chladni":
            return .init(bloom: 0.70, trails: 0.06, mouseRipple: 0.09,
                         mouseLens: 0.12, chroma: 0.16, vignette: 0.30)
        case "aurora":
            return .init(bloom: 0.82, trails: 0.18, mouseRipple: 0.08,
                         mouseLens: 0.10, chroma: 0.16, vignette: 0.10)
        case "kaleidoscope":
            return .init(bloom: 0.86, trails: 0.16, mouseRipple: 0.12,
                         mouseLens: 0.16, chroma: 0.28, vignette: 0.24)
        case "topographic":
            return .init(bloom: 0.34, trails: 0.07, mouseRipple: 0.06,
                         mouseLens: 0.07, chroma: 0.08, vignette: 0.22)
        case "constellation":
            return .init(bloom: 0.95, trails: 0.24, mouseRipple: 0.11,
                         mouseLens: 0.14, chroma: 0.22, vignette: 0.30)
        case "vinyl":
            return .init(bloom: 0.44, trails: 0.05, mouseRipple: 0.14,
                         mouseLens: 0.18, chroma: 0.16, vignette: 0.34)
        default:
            return .init(bloom: 0.58, trails: 0.10, mouseRipple: 0.08,
                         mouseLens: 0.10, chroma: 0.18, vignette: 0.22)
        }
    }
}
