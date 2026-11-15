import Accessibility
import Foundation
import PaintCore
import SwiftUI
import UIKit

/// Every tool, in its group's labelled section, a name beside each (iPad); it scrolls where
/// the screen is too short for all of them (an iPad on its side), its indicator flashing as it
/// comes and its foot fading while there is more below: it ended at Looks, cut in half, with
/// nothing to say Move Number, Writing and Try Painting were there (QA, November 7).
struct RefineToolRail: View {
    let refine: RefineModel
    /// Whether the rail scrolls and has tools below what shows; the screen keeps it while the
    /// rail is away (the full screen).
    @Binding var railHasMore: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: CreateModel { refine.model }

    var body: some View {
        ViewThatFits(in: .vertical) {
            railTools
            ScrollView { railTools }
                .scrollIndicatorsFlash(onAppear: true)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1
                } action: { _, more in
                    railHasMore = more
                }
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .black.opacity(railHasMore ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 56)
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: railHasMore)
                }
        }
        .frame(width: 184)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.leading, 12)
        .padding(.vertical, 12)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .disabled(!model.hasLineArtInput)
    }

    private var railTools: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(RefineGroup.allCases, id: \.self) { kind in
                RefineView.groupName(kind)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.quietInk)
                    .padding(.horizontal, 12)
                    .padding(.top, kind == RefineGroup.allCases.first ? 4 : 14)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(kind.tools, id: \.self) { railRow($0) }
            }
        }
        .padding(8)
    }

    /// A tool in the rail: its symbol and name, filled in the signature color while it's the
    /// finger's.
    @ViewBuilder
    private func railRow(_ kind: RefineTool) -> some View {
        let selected = refine.tool == kind
        let row = Button { refine.toolTapped(kind) } label: {
            HStack(spacing: 10) {
                Image(systemName: refine.symbol(kind))
                    .font(.body.weight(.semibold))
                    .frame(width: 24)
                RefineView.toolName(kind)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    // A long name wraps at larger text rather than shrinking below the others.
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if selected { Capsule().fill(Theme.signature) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.highlight)
        .accessibilityLabel(RefineView.toolName(kind))
        .accessibilityHint(Text(refine.hint(for: kind)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("refine-tool-\(RefineView.toolID(kind))")
        .accessibilityShowsLargeContentViewer { Label { RefineView.toolName(kind) } icon: { Image(systemName: refine.symbol(kind)) } }
        switch kind {
        case .pen: row.gentleTip(.refineDraw, arrowEdge: .leading)
        case .fill: row.gentleTip(.refineFill, arrowEdge: .leading)
        case .shape: row.accessibilityValue(RefineView.shapeName(refine.shape))
        default: row
        }
    }
}

/// A tool's round button (iPhone's row, the Pencil's palette).
struct RefineToolButton: View {
    let refine: RefineModel
    let kind: RefineTool

    var body: some View {
        let button = toolButton(kind, systemImage: refine.symbol(kind), label: RefineView.toolName(kind), id: RefineView.toolID(kind))
        switch kind {
        case .fill: button.gentleTip(.refineFill, arrowEdge: .bottom)
        case .shape: button.accessibilityValue(RefineView.shapeName(refine.shape))
        default: button
        }
    }

    /// A tool, prominent while it's the finger's.
    @ViewBuilder
    private func toolButton(_ tool: RefineTool, systemImage: String, label: Text, id: String) -> some View {
        let selected = refine.tool == tool
        let button = Button { refine.toolTapped(tool) } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 30, height: 30)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
        .accessibilityHint(Text(refine.hint(for: tool)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("refine-tool-\(id)")
        .accessibilityShowsLargeContentViewer { Label { label } icon: { Image(systemName: systemImage) } }
        if selected {
            button.buttonStyle(.glassProminent).tint(Theme.signature)
        } else {
            button.buttonStyle(.glass)
        }
    }
}

/// The tools, a row per group, and the palette in Cells and Paint: beside the Pencil when its
/// double tap or squeeze asks for them.
struct RefinePencilPalette: View {
    @Bindable var refine: RefineModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(RefineGroup.allCases, id: \.self) { kind in
                HStack(spacing: 8) {
                    RefineView.groupName(kind)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 6) {
                            ForEach(kind.tools, id: \.self) { RefineToolButton(refine: refine, kind: $0) }
                        }
                    }
                }
            }
            if refine.group == .cells || refine.group == .paint, let template = refine.base?.template {
                RefinePaletteBar(template: template, current: $refine.currentPaint, picked: $refine.newColors, merge: refine.paletteMerge)
            }
        }
        .padding(16)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .presentationCompactAdaptation(.popover)
        .accessibilityIdentifier("refine-pencil-palette")
    }
}
