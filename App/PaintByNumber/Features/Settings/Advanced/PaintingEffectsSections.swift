import SwiftUI

/// Settings › Advanced: every sound, haptic and flourish of painting on a switch of its own
/// (`PaintingEffect`), in three sections, with a Try button for each sound and haptic. They
/// apply at once, in every painting.
struct PaintingEffectsSections: View {
    @AppStorage(SettingsKey.sounds) private var soundsOn = true
    @AppStorage(SettingsKey.haptics) private var hapticsOn = true
    @AppStorage(PaintingEffect.paintNotes.key) private var paintNotes = true
    @AppStorage(PaintingEffect.colorJingle.key) private var colorJingle = true
    @AppStorage(PaintingEffect.finishFanfare.key) private var finishFanfare = true
    @AppStorage(PaintingEffect.wrongColorSound.key) private var wrongColorSound = true
    @AppStorage(PaintingEffect.fillHaptics.key) private var fillHaptics = true
    @AppStorage(PaintingEffect.wrongColorHaptics.key) private var wrongColorHaptics = true
    @AppStorage(PaintingEffect.finishHaptics.key) private var finishHaptics = true
    @AppStorage(PaintingEffect.fillSparkles.key) private var fillSparkles = true
    @AppStorage(PaintingEffect.finishShine.key) private var finishShine = true

    var body: some View {
        Section {
            ForEach(Self.effects(.sound), id: \.self) { effect in
                EffectRow(effect: effect, isOn: binding(effect), canTry: true)
                    .disabled(!soundsOn)
                    .id(effect == .paintNotes ? "advanced-effects" : effect.rawValue)
            }
        } header: {
            header(.sound, title: String(localized: "advanced.section.sounds", defaultValue: "Sounds",
                                         comment: "Settings › Advanced: header of the section with a switch for each sound painting makes"),
                   identifier: "advanced-reset-sounds")
        } footer: {
            if soundsOn {
                Text("They play in every painting as you paint.")
            } else {
                Text("Sounds are off in Settings, so none of these play.")
            }
        }

        Section {
            ForEach(Self.effects(.haptic), id: \.self) { effect in
                EffectRow(effect: effect, isOn: binding(effect), canTry: FeedbackEngine.shared.supportsHaptics)
                    .disabled(!hapticsOn)
            }
        } header: {
            header(.haptic, title: String(localized: "advanced.section.haptics", defaultValue: "Haptics",
                                          comment: "Settings › Advanced: header of the section with a switch for each haptic painting plays"),
                   identifier: "advanced-reset-haptics")
        } footer: {
            if !FeedbackEngine.shared.supportsHaptics {
                Text("This device can’t play haptics.")
            } else if hapticsOn {
                Text("You feel them in every painting as you paint.")
            } else {
                Text("Haptics are off in Settings, so none of these play.")
            }
        }

        Section {
            ForEach(Self.effects(.visual), id: \.self) { effect in
                EffectRow(effect: effect, isOn: binding(effect), canTry: false)
            }
        } header: {
            header(.visual, title: String(localized: "advanced.section.flourishes", defaultValue: "Sparkles & Shine",
                                          comment: "Settings › Advanced: header of the section with switches for the canvas's sparkles and shine"),
                   identifier: "advanced-reset-flourishes")
        } footer: {
            Text("Neither shows while Reduce Motion is on.")
        }
    }

    private static func effects(_ kind: PaintingEffect.Kind) -> [PaintingEffect] {
        PaintingEffect.allCases.filter { $0.kind == kind }
    }

    private func header(_ kind: PaintingEffect.Kind, title: String, identifier: String) -> some View {
        AdvancedSectionHeader(
            title: title, canReset: Self.effects(kind).contains { !binding($0).wrappedValue }, identifier: identifier
        ) {
            // Removed rather than set, as Advanced's other defaults are.
            for effect in Self.effects(kind) { UserDefaults.standard.removeObject(forKey: effect.key) }
        }
    }

    private func binding(_ effect: PaintingEffect) -> Binding<Bool> {
        switch effect {
        case .paintNotes: $paintNotes
        case .colorJingle: $colorJingle
        case .finishFanfare: $finishFanfare
        case .wrongColorSound: $wrongColorSound
        case .fillHaptics: $fillHaptics
        case .wrongColorHaptics: $wrongColorHaptics
        case .finishHaptics: $finishHaptics
        case .fillSparkles: $fillSparkles
        case .finishShine: $finishShine
        }
    }
}

/// An effect's switch, what it is, and a Try button that plays it once.
private struct EffectRow: View {
    let effect: PaintingEffect
    @Binding var isOn: Bool
    let canTry: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isOn) {
                Text(effect.title)
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityHint(Text(effect.summary))
            .accessibilityIdentifier("advanced-effect-\(effect.rawValue)")
            Text(effect.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            if canTry {
                Button {
                    FeedbackEngine.shared.preview(effect)
                } label: {
                    SwiftUI.Label("Try", systemImage: effect.kind == .haptic ? "hand.tap" : "play.fill")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(Text(String(localized: "advanced.paintingEffect.try", defaultValue: "Try \(effect.title)",
                                                comment: "Settings › Advanced: VoiceOver label of the button that plays a sound or haptic once; the argument is its name, e.g. Color Finished Jingle")))
                .accessibilityIdentifier("advanced-effect-\(effect.rawValue)-try")
            }
        }
        .padding(.vertical, 2)
    }
}

extension PaintingEffect {
    var title: String {
        switch self {
        case .paintNotes:
            String(localized: "advanced.paintingEffect.paintNotes", defaultValue: "Painting Notes",
                   comment: "Settings › Advanced: switch for the musical note played each time paint lands")
        case .colorJingle:
            String(localized: "advanced.paintingEffect.colorJingle", defaultValue: "Color Finished Jingle",
                   comment: "Settings › Advanced: switch for the little tune played when every area of a color is painted")
        case .finishFanfare:
            String(localized: "advanced.paintingEffect.finishFanfare", defaultValue: "Painting Finished Fanfare",
                   comment: "Settings › Advanced: switch for the cascade of notes played when the whole painting is finished")
        case .wrongColorSound:
            String(localized: "advanced.paintingEffect.wrongColorSound", defaultValue: "Wrong Color Sound",
                   comment: "Settings › Advanced: switch for the sound of tapping an area that wants a different paint")
        case .fillHaptics:
            String(localized: "advanced.paintingEffect.fillHaptics", defaultValue: "Fill Haptics",
                   comment: "Settings › Advanced: switch for the vibration felt as paint lands")
        case .wrongColorHaptics:
            String(localized: "advanced.paintingEffect.wrongColorHaptics", defaultValue: "Wrong Color Haptics",
                   comment: "Settings › Advanced: switch for the vibration felt when tapping an area that wants a different paint")
        case .finishHaptics:
            String(localized: "advanced.paintingEffect.finishHaptics", defaultValue: "Finishing Haptics",
                   comment: "Settings › Advanced: switch for the vibrations felt when a color or the painting is finished")
        case .fillSparkles:
            String(localized: "advanced.paintingEffect.fillSparkles", defaultValue: "Fill Sparkles",
                   comment: "Settings › Advanced: switch for the two gold sparkles where an area is filled")
        case .finishShine:
            String(localized: "advanced.paintingEffect.finishShine", defaultValue: "Finishing Shine",
                   comment: "Settings › Advanced: switch for the gloss that sweeps a finished color or painting")
        }
    }

    var summary: String {
        switch self {
        case .paintNotes:
            String(localized: "advanced.paintingEffect.paintNotes.summary",
                   defaultValue: "A note of a gentle tune each time paint lands.",
                   comment: "Settings › Advanced: what the Painting Notes switch does")
        case .colorJingle:
            String(localized: "advanced.paintingEffect.colorJingle.summary",
                   defaultValue: "A little rising tune when the last area of a color is painted.",
                   comment: "Settings › Advanced: what the Color Finished Jingle switch does")
        case .finishFanfare:
            String(localized: "advanced.paintingEffect.finishFanfare.summary",
                   defaultValue: "A cascade of notes when the whole painting is done.",
                   comment: "Settings › Advanced: what the Painting Finished Fanfare switch does")
        case .wrongColorSound:
            String(localized: "advanced.paintingEffect.wrongColorSound.summary",
                   defaultValue: "A soft wooden knock when an area wants a different paint.",
                   comment: "Settings › Advanced: what the Wrong Color Sound switch does")
        case .fillHaptics:
            String(localized: "advanced.paintingEffect.fillHaptics.summary",
                   defaultValue: "A swell you feel as paint lands, fuller for bigger areas.",
                   comment: "Settings › Advanced: what the Fill Haptics switch does")
        case .wrongColorHaptics:
            String(localized: "advanced.paintingEffect.wrongColorHaptics.summary",
                   defaultValue: "A soft double tap when an area wants a different paint.",
                   comment: "Settings › Advanced: what the Wrong Color Haptics switch does")
        case .finishHaptics:
            String(localized: "advanced.paintingEffect.finishHaptics.summary",
                   defaultValue: "Bright taps when a color is finished, a rising shimmer when the painting is.",
                   comment: "Settings › Advanced: what the Finishing Haptics switch does")
        case .fillSparkles:
            String(localized: "advanced.paintingEffect.fillSparkles.summary",
                   defaultValue: "Two gold sparkles pop where an area is filled.",
                   comment: "Settings › Advanced: what the Fill Sparkles switch does")
        case .finishShine:
            String(localized: "advanced.paintingEffect.finishShine.summary",
                   defaultValue: "A gloss sweeps a color when it is finished, and the whole painting when it is done.",
                   comment: "Settings › Advanced: what the Finishing Shine switch does")
        }
    }
}
