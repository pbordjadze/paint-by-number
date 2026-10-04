import Foundation

/// A slider of Settings › Advanced: its range (linear, or on a log₂ scale for multipliers), the
/// rounding of its values, the step one VoiceOver adjustment moves, and how values read. The
/// track works in positions 0…1; values near the default snap to it.
nonisolated struct SliderSpec: Sendable {
    enum Format: Sendable {
        case percent, pixels, multiplier
    }

    let range: ClosedRange<Double>
    let defaultValue: Double
    var logarithmic = false
    /// Values are rounded to multiples of this.
    let quantum: Double
    /// One VoiceOver adjustment: in value units, or in log₂ units on a logarithmic slider.
    let accessibilityStep: Double
    let format: Format

    /// Within this fraction of the track the default catches the thumb.
    static let detent = 0.02

    private func scaled(_ value: Double) -> Double { logarithmic ? log2(max(value, 1e-6)) : value }
    private func unscaled(_ value: Double) -> Double { logarithmic ? exp2(value) : value }

    func position(of value: Double) -> Double {
        let lo = scaled(range.lowerBound), hi = scaled(range.upperBound)
        guard hi > lo else { return 0 }
        return min(max((scaled(value) - lo) / (hi - lo), 0), 1)
    }

    /// The value at a track position: rounded to `quantum`, the default when it is that close.
    func value(at position: Double) -> Double {
        let p = min(max(position, 0), 1)
        if abs(p - self.position(of: defaultValue)) < Self.detent { return defaultValue }
        let lo = scaled(range.lowerBound), hi = scaled(range.upperBound)
        return clamped((unscaled(lo + (hi - lo) * p) / quantum).rounded() * quantum)
    }

    /// `value` moved by `steps` VoiceOver adjustments, which land on multiples of the step
    /// (on a logarithmic slider, of the step in log₂ units: 1×, 1.19×, 1.41×, 1.68×, 2×), so
    /// rounding never makes them drift.
    func value(_ value: Double, adjustedBy steps: Int) -> Double {
        let index = (scaled(value) / accessibilityStep).rounded() + Double(steps)
        return clamped((unscaled(index * accessibilityStep) / quantum).rounded() * quantum)
    }

    private func clamped(_ value: Double) -> Double { min(max(value, range.lowerBound), range.upperBound) }

    func text(_ value: Double) -> String {
        switch format {
        case .percent: value.formatted(.percent.precision(.fractionLength(0)))
        case .pixels: AdvancedText.pixels(Int(value.rounded()))
        case .multiplier: AdvancedText.multiplier(value)
        }
    }
}

/// The Line Weight slider of a coloring book (`LineAppearance.coloringBookWeight`): half to
/// twice the designed line, on a log scale with the default in the middle.
nonisolated let coloringBookWeightSlider = SliderSpec(
    range: Double(LineAppearance.coloringBookWeightRange.lowerBound)...Double(LineAppearance.coloringBookWeightRange.upperBound),
    defaultValue: Double(LineAppearance.default.coloringBookWeight), logarithmic: true, quantum: 0.05, accessibilityStep: 0.25,
    format: .multiplier)
