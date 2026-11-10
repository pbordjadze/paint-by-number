import Foundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// First step of the create flow, the Paint page (painting-company row 239, "Paint Now, through
/// the Shelf's door"): one shelf of pictures. Tonight's Picture (a library painting, another each
/// day) large at the top, then Your Own: a photo from the system picker, the camera, a blank page
/// and, in SideStore and Debug builds, a drawing on paper; then The Library, its paintings
/// and photographs. A picture picked opens as a painting with no preview step
/// (`CreateModel.paintsNow`); a blank page opens the drawing tools (`CreateModel.loadScratch()`).
///
/// No inline photo picker: the Shelf scrolls, and the inline picker scrolls out of process,
/// which a scroll view around it can't arbitrate (a drag on it moved neither); on iPhone its grid
/// never took a tap either (Sept 30, Oct 4 and 9). A Photo presents the full system picker.
struct PhotoSourceView: View {
    let model: CreateModel
    var onClose: () -> Void
    var onPicked: () -> Void

    @State private var browsedItem: PhotosPickerItem?
    @State private var isBrowsingAll = false
    @State private var isShowingCamera = false
    #if UNRELEASED
    /// Start from a Drawing (painting-company row 190): A Drawing on Paper opens the system
    /// picker for a photo of a drawing, which `CreateModel.load(drawing:)` cleans and traces. The
    /// same picker and camera serve both; this says which way the next pick goes.
    @State private var picksDrawing = false
    #endif
    /// Blank Page was tapped before Unlimited Paintings, which the drawing tools come with, was bought.
    @State private var offersRefineUnlock = false
    @Environment(UnlimitedPaintings.self) private var paintings
    @State private var width: CGFloat = 0
    @State private var height: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Tiles widen with the text size, so a caption keeps room at the largest sizes.
    @ScaledMetric(relativeTo: .subheadline) private var tileMinimumWidth: CGFloat = 150
    @ScaledMetric(relativeTo: .subheadline) private var ownTileMinimumWidth: CGFloat = 140

    private var isWide: Bool { width >= 600 }
    private var horizontalPadding: CGFloat { isWide ? 32 : 20 }
    /// At accessibility sizes the title leaves the bar for a line of its own atop the page.
    private var titleOnPage: Bool { dynamicTypeSize.isAccessibilitySize }
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if titleOnPage {
                        Text("Paint")
                            .font(.display(.title))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if let tonight = Sample.tonight() { tonightSection(tonight) }
                    yourOwnSection
                    librarySection
                }
                // Room for the press scale and hover lift inside the scroll view's clip.
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            #if DEBUG
            .onChange(of: width, initial: true) {
                if let kind = ShellDemo.current?.samplesSection { proxy.scrollTo(kind, anchor: .top) }
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.paper)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            width = size.width
            height = size.height
        }
        .navigationTitle("Paint")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: titleOnPage ? .title : nil)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        // The full picker, for A Photo and A Drawing on Paper.
        .photosPicker(isPresented: $isBrowsingAll, selection: $browsedItem, matching: .images, preferredItemEncoding: .current)
        .onChange(of: browsedItem) { _, item in
            guard let item else { return }
            browsedItem = nil
                #if UNRELEASED
            if picksDrawing {
                PaintTips.photoChosen()
                model.paintsNow = true
                model.load(drawing: item)
                onPicked()
                return
            }
                #endif
            PaintTips.photoChosen()
            model.paintsNow = true
            model.load(item: item)
            onPicked()
        }
        .onAppear { PaintTips.newPaintingOpened() }
        .onDisappear { PaintTips.desk.leave(.newPainting) }
        .modifier(RefineUnlockOffer(isPresented: $offersRefineUnlock, unlocked: startFromScratch))
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { data in
                PaintTips.photoChosen()
                model.paintsNow = true
                #if UNRELEASED
                if picksDrawing { model.load(drawingData: data) } else { model.load(imageData: data) }
                #else
                model.load(imageData: data)
                #endif
                onPicked()
            } onFailure: {
                model.fail(.cameraCapture)
                onPicked()
            }
            .ignoresSafeArea()
        }
    }

    // MARK: The shelf

    /// Tonight's Picture: one painting from the library, large, another each day.
    private func tonightSection(_ tonight: Sample) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("Tonight’s Picture", style: isWide ? .title2 : .title3)
                Text("A different picture every day")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            Button { pick(tonight) } label: { SampleTile(sample: tonight) }
                .buttonStyle(PressableCardStyle())
                .frame(maxWidth: tonightWidth)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("tonights-picture")
        }
    }

    /// The painter's own ways in: a photo, the camera, a blank page and, in SideStore and Debug
    /// builds, a drawing on paper.
    private var yourOwnSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Your Own", style: isWide ? .title2 : .title3)
            // A grid, not a row that scrolls: every way in shows, wrapping onto a second line on a
            // phone and onto one each at the largest text sizes (the Mac's QA: Blank Page was
            // never seen past the row's edge).
            LazyVGrid(columns: [GridItem(.adaptive(minimum: ownTileWidth), spacing: 12, alignment: .top)], spacing: 12) {
                Button(action: browseAll) {
                    OwnTile(title: Text("A Photo"), systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("choose-photo")
                if cameraAvailable {
                    Button(action: showCamera) {
                        OwnTile(title: Text("Take Photo"), systemImage: "camera")
                    }
                    .accessibilityIdentifier("take-photo")
                }
                #if UNRELEASED
                Button {
                    picksDrawing = true
                    isBrowsingAll = true
                } label: {
                    OwnTile(title: Text("A Drawing on Paper"), systemImage: "doc.viewfinder")
                }
                .accessibilityHint(Text("A photo of a drawing, traced into a painting"))
                .accessibilityIdentifier("choose-drawing")
                #endif
                Button {
                    if paintings.locksRefine { offersRefineUnlock = true } else { startFromScratch() }
                } label: {
                    OwnTile(title: Text("Blank Page"), systemImage: "pencil.and.scribble")
                }
                .accessibilityHint(Text("Draw your own picture on a blank page"))
                .accessibilityIdentifier("from-scratch")
            }
            .buttonStyle(PressableCardStyle())
        }
    }

    /// Tonight's Picture's width: across the page, but never taller than about 45% of the
    /// window, so its name and Your Own show beneath it on a phone held sideways too.
    private var tonightWidth: CGFloat {
        let page = max(0, width - 2 * horizontalPadding)
        guard height > 0 else { return page }
        return min(page, height * 0.45 * 4 / 3)
    }

    /// Your Own's least tile width: two to a phone's row, one at the largest text sizes.
    private var ownTileWidth: CGFloat {
        let column = max(0, width - 2 * horizontalPadding - 8)
        return min(column, ownTileMinimumWidth)
    }

    /// The library: its paintings, then its photographs.
    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle("The Library", style: isWide ? .title2 : .title3)
            ForEach(Sample.Kind.allCases, id: \.self) { kind in
                let samples = Sample.all(of: kind)
                if !samples.isEmpty { samplesSection(kind, samples: samples) }
            }
        }
    }

    private func samplesSection(_ kind: Sample.Kind, samples: [Sample]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(kind)
                .id(kind)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 14)], spacing: 14) {
                ForEach(samples) { sample in
                    Button { pick(sample) } label: { SampleTile(sample: sample) }
                        .buttonStyle(PressableCardStyle())
                        .accessibilityIdentifier("library-picture")
                }
            }
        }
    }

    @ViewBuilder
    private func sectionTitle(_ kind: Sample.Kind) -> some View {
        switch kind {
        case .painting: SectionTitle("Paintings", style: .headline)
        case .photograph: SectionTitle("Photographs", style: .headline)
        }
    }

    /// The grid's minimum tile width, never wider than the column (the press-scale padding
    /// taken off), so a tile scaled up for a large text size still fits.
    private var tileWidth: CGFloat {
        let column = width - 2 * horizontalPadding - 8
        return column > 0 ? min(tileMinimumWidth, column) : tileMinimumWidth
    }

    // MARK: Picking

    private func pick(_ sample: Sample) {
        PaintTips.photoChosen()
        model.paintsNow = true
        model.load(sample: sample)
        onPicked()
    }

    /// The full picker, for a photo.
    private func browseAll() {
        #if UNRELEASED
        picksDrawing = false
        #endif
        isBrowsingAll = true
    }

    /// The camera, for a photo.
    private func showCamera() {
        #if UNRELEASED
        picksDrawing = false
        #endif
        isShowingCamera = true
    }

    /// A blank page, straight into the drawing tools.
    private func startFromScratch() {
        PaintTips.photoChosen()
        model.paintsNow = false
        // Back from a page drawn on and Blank Page again: that page, not a fresh one.
        if model.hasScratchDrawing { model.reopenScratch() } else { model.loadScratch() }
        onPicked()
    }
}

/// One of Your Own's ways in: a small card with its symbol and name.
private struct OwnTile: View {
    let title: Text
    let systemImage: String
    @ScaledMetric(relativeTo: .subheadline) private var side: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            title
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Its grid cell's width, taller for a name that wraps.
        .frame(maxWidth: .infinity, minHeight: side * 0.8, alignment: .topLeading)
        .padding(12)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1) }
        .contentShape(.rect(cornerRadius: 18, style: .continuous))
        .contentShape(.hoverEffect, .rect(cornerRadius: 18, style: .continuous))
        .hoverEffect(.lift)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct SectionTitle: View {
    let title: LocalizedStringKey
    let style: Font.TextStyle
    init(_ title: LocalizedStringKey, style: Font.TextStyle = .title3) {
        self.title = title
        self.style = style
    }

    var body: some View {
        Text(title)
            .font(.display(style))
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SampleTile: View {
    let sample: Sample
    @State private var image: CGImage?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                caption
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Starts above the caption and is dark by its first line: white spray or sky
                    // behind a title (The Great Wave's) left it unreadable. Dark enough there for
                    // white words over a white picture to pass WCAG AA (QA, November 7: 0.5 gave
                    // 3.9:1).
                    .background(alignment: .bottom) {
                        LinearGradient(
                            stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.62), location: 0.45),
                                    .init(color: .black.opacity(0.8), location: 1)],
                            startPoint: .top, endPoint: .bottom)
                            .padding(.top, -28)
                    }
                    .opacity(captionsBelow ? 0 : 1)
            }
            .modifier(CaptionBelow(shows: captionsBelow) { captionBelow })
            .background(Theme.surface)
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
            .contentShape(.rect(cornerRadius: 18, style: .continuous))
            .contentShape(.hoverEffect, .rect(cornerRadius: 18, style: .continuous))
            .hoverEffect(.lift)
            .task {
                let loaded = await SampleImages.shared.load(sample, maxPixelSize: 640)
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }

    /// At accessibility sizes the caption on the picture ran out of room and was cut short: it
    /// goes under the picture, as the gallery's cards have theirs, and wraps whole.
    private var captionsBelow: Bool { dynamicTypeSize.isAccessibilitySize }

    private var captionBelow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sample.title)
                .font(.subheadline.weight(.semibold))
            if let painter {
                Text(painter)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The title, and under a painting's its painter when the tile has room for both: long
    /// text and large sizes drop the painter first, then truncate the title.
    private var caption: some View {
        ViewThatFits(in: .vertical) {
            if let painter {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    Text(painter)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .opacity(0.9)
                }
            }
            title
        }
    }

    private var title: some View {
        Text(sample.title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
    }

    /// A painting's creator, shown under its title: the painter is part of how people know a
    /// painting, a photographer rarely is. VoiceOver hears the creator of both.
    private var painter: String? {
        guard let provenance = sample.provenance, provenance.kind == .painting else { return nil }
        return provenance.creator
    }

    private var accessibilityLabel: String {
        guard let creator = sample.provenance?.creator else {
            return sample.title
        }
        return String(localized: "create.sample.labelWithCreator", defaultValue: "\(sample.title), \(creator)",
                      comment: "VoiceOver label of a picture's tile on the Paint page (Tonight’s Picture, The Library), under its section's heading; the arguments are its title and who made it, e.g. “The Great Wave, Katsushika Hokusai”")
    }
}

/// A sample tile's caption under its picture rather than on it (`SampleTile.captionsBelow`).
private struct CaptionBelow<Caption: View>: ViewModifier {
    let shows: Bool
    @ViewBuilder let caption: () -> Caption

    func body(content: Content) -> some View {
        if shows {
            VStack(alignment: .leading, spacing: 0) {
                content.clipped()
                caption()
            }
        } else {
            content
        }
    }
}
