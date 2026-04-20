import Foundation
import simd
import SwiftUI

/// Stores per-preset parameter values, persists to UserDefaults, and packs them
/// into the GPU-ready `PresetParams` struct each frame.
final class ParamStore: ObservableObject {
    @Published private var values: [String: [String: ParamValue]] = [:]   // presetId -> key -> value

    private let defaultsKey = "MusicViz.ParamStore.v1"

    init() {
        load()
    }

    // MARK: - Read / write

    func binding(presetId: String, spec: ParamSpec) -> Binding<ParamValue> {
        Binding(
            get: { self.value(presetId: presetId, spec: spec) },
            set: { self.set($0, presetId: presetId, key: spec.id) }
        )
    }

    func value(presetId: String, spec: ParamSpec) -> ParamValue {
        values[presetId]?[spec.id] ?? spec.defaultValue
    }

    func set(_ value: ParamValue, presetId: String, key: String) {
        var bucket = values[presetId] ?? [:]
        bucket[key] = value
        values[presetId] = bucket
        save()
    }

    func reset(presetId: String, key: String) {
        guard var bucket = values[presetId] else { return }
        bucket.removeValue(forKey: key)
        values[presetId] = bucket
        save()
    }

    func resetAll(presetId: String) {
        values[presetId] = [:]
        save()
    }

    // MARK: - Packing for shader

    /// Pack current values for the given preset into the GPU-ready struct.
    func packed(for preset: Preset) -> PresetParams {
        var params = PresetParams()
        for spec in preset.params {
            let v = value(presetId: preset.id, spec: spec)
            switch spec.slot {
            case .float(let i) where i >= 0 && i < 16:
                let comp = i % 4
                switch i / 4 {
                case 0: params.p0[comp] = v.asFloat
                case 1: params.p1[comp] = v.asFloat
                case 2: params.p2[comp] = v.asFloat
                case 3: params.p3[comp] = v.asFloat
                default: break
                }
            case .color(let i) where i >= 0 && i < 4:
                let rgba = v.asColor
                switch i {
                case 0: params.c0 = rgba
                case 1: params.c1 = rgba
                case 2: params.c2 = rgba
                case 3: params.c3 = rgba
                default: break
                }
            default: break
            }
        }
        return params
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([String: [String: ParamValue]].self, from: data)
            self.values = decoded
        } catch {
            NSLog("MusicViz: failed to load params: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(values)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            NSLog("MusicViz: failed to save params: \(error)")
        }
    }
}

/// GPU-side parameter block matching `PresetParams` in Shaders.metal.
/// Layout: four float4 slots for scalars (16 floats addressed via slot 0..15),
/// followed by four float4 colors. Total 128 bytes.
struct PresetParams {
    var p0: SIMD4<Float> = .zero
    var p1: SIMD4<Float> = .zero
    var p2: SIMD4<Float> = .zero
    var p3: SIMD4<Float> = .zero
    var c0: SIMD4<Float> = .init(1, 1, 1, 1)
    var c1: SIMD4<Float> = .init(1, 1, 1, 1)
    var c2: SIMD4<Float> = .init(1, 1, 1, 1)
    var c3: SIMD4<Float> = .init(1, 1, 1, 1)
}
