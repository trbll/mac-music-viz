import SwiftUI

/// Translucent panel/chip backgrounds using `.ultraThinMaterial`.
///
/// NOTE: On macOS 26+ / Xcode 26 these should be upgraded to Liquid Glass
/// (`.glassEffect(_:in:)`, `GlassEffectContainer`). The current SDK (Xcode 16.x)
/// doesn't ship those symbols, so we use the thin-material fallback for now.
extension View {
    func panelBackground<S: Shape>(_ shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(.white.opacity(0.08), lineWidth: 0.5))
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 8)
    }

    func chipBackground() -> some View {
        self
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
    }
}
