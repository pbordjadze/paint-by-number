import PaintCore
import SwiftUI

/// Refine's Edit Paint (`RefineTool.editPaint`): the current paint (picked in the palette,
/// `RefinePaletteBar`, or by a tap on its area) takes a new color from the system color picker, its
/// family moving with it while Similar Colors Too is on; once any paint has changed, Photo’s Colors
/// puts the photo's own back. Shapes, lines and numbers never change. Its Looks, a row of moods over
/// every paint, left on November 17, 2026 (painting-company's cut list: the look picker Paul set
/// aside, and Blend paints new paintings prettily without a choice); a painting that has a look
/// keeps it, and Photo’s Colors takes it out.
struct RefineColorsPanel: View {
    /// The template on screen.
    let template: Template
    /// The edits the template on screen has: whether any color changed.
    let edits: [TemplateEditor.Edit]
    /// The paint picked (an index of `template.palette`).
    @Binding var paint: Int?
    @Binding var family: Bool
    let change: (RefineColors) -> Void

    @Environment(\.self) private var environment
    /// The picked paint's color when it was picked: a repaint's `from` while the picker moves.
    @State private var from: SIMD3<Float>?
    /// The picker's last color, laid once it has rested a moment or as the panel goes.
    @State private var pending = RefinePendingPick()

    /// Whether the painting is in the photo's own colors: no look, no repaint.
    private var inPhotoColors: Bool { RefineColors.withoutColors(edits).count == edits.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            picker
            if !inPhotoColors { photoColors }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .frame(maxWidth: 720)
        .onAppear { pick(paint) }
        .onChange(of: paint) { _, new in pick(new) }
        // Photo's Colors changed the paints: the next repaint starts from the color shown. Only
        // this picker's own repaint, still moving, keeps the color it started from.
        .onChange(of: template.palette) { _, _ in
            if case .repaint(let started, _, _)? = edits.last, started == from { return }
            pick(paint)
        }
        .onDisappear { pending.flush() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("refine-colors")
    }

    /// The current paint's color, and its family's.
    @ViewBuilder
    private var picker: some View {
        if let paint, paint < template.palette.count {
            HStack(spacing: 12) {
                Text(Self.paintTitle(paint))
                    .font(.footnote.weight(.semibold))
                ColorPicker(selection: color(of: paint), supportsOpacity: false) { Text("Color") }
                    .labelsHidden()
                    .accessibilityIdentifier("refine-colors-picker")
                Spacer(minLength: 8)
                Toggle(isOn: $family) { Text("Similar colors too") }
                    .font(.footnote)
                    .fixedSize()
                    .tint(Theme.signature)
                    .accessibilityIdentifier("refine-colors-family")
            }
        } else {
            Text("Pick a paint in the palette, or tap an area.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Takes every new color and look out, the photo's own colors back; colors given single
    /// areas (the Bucket, the Paint Brush, Only This Area) stay.
    private var photoColors: some View {
        Button {
            pending.drop()
            FeedbackEngine.shared.selectionChanged()
            change(.photo)
        } label: {
            SwiftUI.Label("Photo’s Colors", systemImage: "arrow.uturn.backward")
                .font(.footnote)
        }
        .buttonStyle(.bordered)
        .tint(Theme.signature)
        .accessibilityHint(Text(String(localized: "refine.colors.photo.hint", defaultValue: "Puts the photo’s own colors back.",
                                       comment: "Refine screen, Edit Paint: VoiceOver hint of Photo’s Colors, which takes every new color and look out")))
        .accessibilityIdentifier("refine-colors-photo")
    }

    // MARK: Paints

    static func paintTitle(_ index: Int) -> String {
        String(localized: "refine.colors.paint", defaultValue: "Paint \(index + 1)",
               comment: "Refine screen, Colors: the paint picked to take a new color, by its number; the argument is the number")
    }

    /// The picked paint's color as the picker shows it; a color picked is laid once the picker
    /// rests a moment (`RefinePendingPick`).
    private func color(of index: Int) -> Binding<Color> {
        Binding(
            get: { PaletteBar.paint(template, index) },
            set: { color in
                guard let from else { return }
                let resolved = color.resolve(in: environment)
                let to = ColorScience.linearSRGBToOKLab(SIMD3(resolved.linearRed, resolved.linearGreen, resolved.linearBlue))
                let family = family
                pending.pick { change(.repaint(from: from, to: to, family: family)) }
            })
    }

    /// The paint whose color the picker changes; a color still waiting is laid on the one before.
    private func pick(_ index: Int?) {
        pending.flush()
        from = index.flatMap { $0 < template.palette.count ? template.palette[$0].oklab : nil }
    }
}

/// The system color picker's last color, laid once the picker rests a moment (`rest`), so a drag
/// across the spectrum doesn't queue an edit per step; and at once when the view it was picked
/// in goes (`flush`), so the last color picked is never dropped. Refine's card and its Edit Paint
/// share it.
final class RefinePendingPick {
    /// How long the picker rests before its color is laid.
    static let rest: Duration = .milliseconds(150)

    private var waiting: (() -> Void)?
    private var timer: Task<Void, Never>?

    /// A color picked: `lay` lays it, once the picker rests, in place of any still waiting.
    func pick(_ lay: @escaping () -> Void) {
        waiting = lay
        timer?.cancel()
        timer = Task {
            try? await Task.sleep(for: Self.rest)
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    /// Lays the color waiting, if one is, now.
    func flush() {
        timer?.cancel()
        timer = nil
        guard let lay = waiting else { return }
        waiting = nil
        lay()
    }

    /// Forgets the color waiting: something else was chosen in its place.
    func drop() {
        timer?.cancel()
        timer = nil
        waiting = nil
    }
}
