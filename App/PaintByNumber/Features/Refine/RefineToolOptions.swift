import Accessibility
import Foundation
import PaintCore
import SwiftUI
import UIKit

/// What the picked tool offers above the tools: Shapes' figures, Snap where lines join, the
/// Pen's Color from Photo, and the current paint's color.
struct RefineToolOptions: View {
    @Bindable var refine: RefineModel
    /// The tools stand in a column beside the picture (`RefineView.usesSide`), the options bare
    /// on its paper.
    let usesSide: Bool
    /// The painter's text size, as the screen reads it: the Studio clamps its own at `.xxLarge`,
    /// so the environment here never says, and the options lay out as a column from the
    /// accessibility sizes on.
    let typeSize: DynamicTypeSize
    /// The switches and sizes, the painter's or a practice canvas's own (`RefineView`'s settings).
    @Binding var snaps: Bool
    @Binding var penColors: Bool
    @Binding var brushSize: Double
    @Binding var eraserSize: Double
    @Binding var penSmoothing: Double

    private var model: CreateModel { refine.model }

    var body: some View {
        switch refine.tool {
        case .pen:
            optionBar {
                snapToggle
                penColorsToggle
            } more: {
                Text("Smoothing")
                Slider(value: $penSmoothing, in: 0...1)
                    .frame(width: 140)
                    .accessibilityLabel(Text("Smoothing"))
                    .accessibilityValue(Text(penSmoothing.formatted(.percent.precision(.fractionLength(0)))))
                    .accessibilityHint(Text(String(
                        localized: "refine.smoothing.hint", defaultValue: "Evens out a wobbly line: the line trails your finger a little. Off draws exactly as you draw.",
                        comment: "Refine screen, the Pen's options: VoiceOver hint of Smoothing, a slider from off to full (Procreate calls it StreamLine)")))
                    .accessibilityIdentifier("refine-pen-smoothing")
            }
        case .shape:
            optionBar {
                HStack(spacing: 6) {
                    ForEach(RefineShape.allCases, id: \.self) { shapeOption($0) }
                }
            } more: {
                snapToggle
                penColorsToggle
            }
        case .cellEdge:
            optionBar { snapToggle }
        case .brush:
            optionBar { sizeSlider($brushSize, id: "refine-brush-size") }
        case .eraser, .smartEraser:
            optionBar { sizeSlider($eraserSize, id: "refine-eraser-size") }
        case .editPaint:
            if let base = refine.base {
                RefineColorsPanel(
                    template: base.template, edits: base.refinements.edits,
                    paint: currentIndexBinding, family: $refine.colorFamily, change: refine.recolor)
                    .disabled(model.phase == .generating || !model.hasLineArtInput)
                    .transition(.opacity)
            }
        default:
            EmptyView()
        }
    }

    /// The tool's options in a capsule.
    private func optionBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        optionBar(content, more: { EmptyView() })
    }

    /// The tool's options in a capsule; `more` beside them where the width holds both, else under
    /// them, else a column. From the accessibility sizes on, each option has a line of its own
    /// and a slider's name stands over it: the rows ran into each other and out of their capsule.
    private func optionBar<Content: View, More: View>(
        @ViewBuilder _ content: () -> Content, @ViewBuilder more: () -> More
    ) -> some View {
        let content = content(), more = more()
        let column = VStack(alignment: .leading, spacing: 10) {
            content
            more
        }
        .frame(maxWidth: 320)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6)
        return Group {
            if typeSize.isAccessibilitySize {
                column
            } else {
                // The column also where long words (a translation) leave even two rows wider
                // than a phone: fixed, they laid the whole screen out wider than the window.
                // Each option at its own width in a row: two switches shared the row in halves,
                // Snap's word far from its switch and "Color from Photo" broken in two though the
                // row had room (QA, November 7).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        Group { content }.fixedSize()
                        Group { more }.fixedSize()
                    }
                    .fixedSize()
                    VStack(spacing: 8) {
                        HStack(spacing: 16) { Group { content }.fixedSize() }
                        HStack(spacing: 10) { Group { more }.fixedSize() }
                    }
                    .fixedSize()
                    column
                }
            }
        }
        .font(.footnote)
        .toggleStyle(.switch)
        .tint(Theme.signature)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        // Beside the picture, on the paper: boxed, the column was all boxes.
        .glassEffect(usesSide ? .identity : .regular, in: .rect(cornerRadius: 22))
        .disabled(!model.hasLineArtInput)
    }

    /// A brush's or an eraser's Size: its radius on screen, in points ([ and ] step it too).
    @ViewBuilder
    private func sizeSlider(_ size: Binding<Double>, id: String) -> some View {
        Text("Size")
        Slider(value: size, in: RefineView.sizes)
            .frame(width: 160)
            .accessibilityLabel(Text("Size"))
            .accessibilityValue(Text(String(
                localized: "refine.brush.size", defaultValue: "\(Int(size.wrappedValue.rounded())) points",
                comment: "Refine screen, the Paint Brush's and the Eraser's options: VoiceOver value of their Size slider, the radius on screen in points; the argument is the number")))
            .accessibilityIdentifier(id)
    }

    /// The Pen's and Shapes' Color from Photo: a figure's pieces take the photo's colors as a
    /// drawn line's do (`inked`), so the switch shows with both. A blank page has no photo to
    /// color from, so none there (the Mac's QA, November 9).
    @ViewBuilder
    private var penColorsToggle: some View {
        if !model.isScratch {
            penColorsSwitch
        }
    }

    private var penColorsSwitch: some View {
        Toggle(isOn: $penColors) { Text("Color from Photo") }
            .accessibilityHint(Text(String(
                localized: "refine.penColors.hint", defaultValue: "Gives the areas a line divides the photo’s colors there.",
                comment: "Refine screen, the Pen's options: VoiceOver hint of Color from Photo, which makes each part of an area a drawn line divides take the photo's color there")))
            .accessibilityIdentifier("refine-pen-colors")
    }

    private var snapToggle: some View {
        Toggle(isOn: $snaps) { Text("Snap") }
            .accessibilityHint(Text(String(
                localized: "refine.snap.hint", defaultValue: "Moves the end of a line onto a line it lands near.",
                comment: "Refine screen, a drawing tool's options: VoiceOver hint of Snap, which moves a drawn line's end onto a line it lands within a fingertip of")))
            .accessibilityIdentifier("refine-snap")
    }

    /// One of Shapes' figures: picks it.
    private func shapeOption(_ kind: RefineShape) -> some View {
        let selected = refine.shape == kind
        let button = Button {
            FeedbackEngine.shared.selectionChanged()
            refine.pickShape(kind)
        } label: {
            Label { RefineView.shapeName(kind) } icon: { Image(systemName: kind.systemImage) }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 26, height: 26)
        }
        .buttonBorderShape(.circle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("refine-shape-\(kind)")
        return Group {
            if selected {
                button.buttonStyle(.glassProminent).tint(Theme.signature)
            } else {
                button.buttonStyle(.glass)
            }
        }
    }

    private var currentIndexBinding: Binding<Int?> {
        Binding(
            get: { refine.currentIndex },
            set: { index in
                guard let index, let palette = refine.base?.template.palette, index < palette.count else { return }
                refine.currentPaint = palette[index].oklab
            })
    }
}
