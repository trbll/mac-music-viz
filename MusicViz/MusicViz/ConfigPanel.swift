import SwiftUI

struct ConfigPanel: View {
    @ObservedObject var presets: PresetManager
    @ObservedObject var params: ParamStore
    let onClose: () -> Void

    var body: some View {
        let preset = presets.current
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider().opacity(0.3)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(preset.params) { spec in
                        ParamRow(presetId: preset.id, spec: spec, params: params)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider().opacity(0.3)

            Button {
                params.resetAll(presetId: preset.id)
            } label: {
                Label("Reset all to defaults", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
        }
        .padding(18)
        .frame(width: 300)
        .panelBackground(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.trailing, 16)
        .padding(.vertical, 16)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(presets.current.name)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("Effect settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.secondary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }
}

// MARK: - ParamRow

private struct ParamRow: View {
    let presetId: String
    let spec: ParamSpec
    @ObservedObject var params: ParamStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(spec.label)
                    .font(.callout)
                Spacer()
                valueLabel
                Button {
                    params.reset(presetId: presetId, key: spec.id)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }

            control
        }
    }

    @ViewBuilder
    private var control: some View {
        switch spec.kind {
        case .slider(let lo, let hi):
            Slider(
                value: Binding<Float>(
                    get: { params.value(presetId: presetId, spec: spec).asFloat },
                    set: { params.set(.float($0), presetId: presetId, key: spec.id) }
                ),
                in: lo...hi
            )
        case .stepper(let lo, let hi):
            Stepper(
                value: Binding<Int>(
                    get: {
                        if case .int(let v) = params.value(presetId: presetId, spec: spec) {
                            return v
                        }
                        return Int(params.value(presetId: presetId, spec: spec).asFloat)
                    },
                    set: { params.set(.int($0), presetId: presetId, key: spec.id) }
                ),
                in: lo...hi
            ) {
                EmptyView()
            }
            .labelsHidden()
        case .toggle:
            Toggle(isOn: Binding(
                get: {
                    if case .bool(let v) = params.value(presetId: presetId, spec: spec) {
                        return v
                    }
                    return false
                },
                set: { params.set(.bool($0), presetId: presetId, key: spec.id) }
            )) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)
        case .color:
            ColorPicker("", selection: Binding(
                get: { Color(rgba: params.value(presetId: presetId, spec: spec).asColor) },
                set: { params.set(.color($0.toRGBA()), presetId: presetId, key: spec.id) }
            ), supportsOpacity: false)
            .labelsHidden()
        case .picker(let options):
            Picker("", selection: Binding<Int>(
                get: {
                    if case .int(let v) = params.value(presetId: presetId, spec: spec) { return v }
                    return 0
                },
                set: { params.set(.int($0), presetId: presetId, key: spec.id) }
            )) {
                ForEach(0..<options.count, id: \.self) { i in
                    Text(options[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
        case .palette(let count):
            HStack(spacing: 10) {
                ForEach(0..<count, id: \.self) { i in
                    ColorPicker("", selection: paletteBinding(at: i, count: count),
                                supportsOpacity: false)
                        .labelsHidden()
                        .fixedSize()
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func paletteBinding(at i: Int, count: Int) -> Binding<Color> {
        Binding(
            get: {
                let stops = params.value(presetId: presetId, spec: spec).asPalette
                guard i < stops.count else { return .white }
                return Color(rgba: stops[i])
            },
            set: { newColor in
                var stops = params.value(presetId: presetId, spec: spec).asPalette
                while stops.count < count { stops.append(.init(1, 1, 1, 1)) }
                stops[i] = newColor.toRGBA()
                params.set(.palette(stops), presetId: presetId, key: spec.id)
            }
        )
    }

    @ViewBuilder
    private var valueLabel: some View {
        let v = params.value(presetId: presetId, spec: spec)
        switch spec.kind {
        case .slider:
            Text(String(format: "%.2f", v.asFloat))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        case .stepper:
            if case .int(let i) = v {
                Text("\(i)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }
}
