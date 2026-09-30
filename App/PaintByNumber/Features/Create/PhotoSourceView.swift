import Photos
import PhotosUI
import SwiftUI
import UIKit

/// First step of the create flow: the photo library inline, the camera, and samples.
///
/// The inline picker is the page's primary content and fills the remaining height. Compact
/// windows switch between it and the samples with a segmented control; wide windows show the
/// samples in a scrolling column beside it. "Browse All…" presents the full system picker.
struct PhotoSourceView: View {
    enum Pane: Hashable { case photos, samples }

    let model: CreateModel
    var onClose: () -> Void
    var onPicked: () -> Void

    @State private var pane: Pane
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var browsedItem: PhotosPickerItem?
    @State private var isBrowsingAll = false
    @State private var isShowingCamera = false
    @State private var width: CGFloat = 0

    init(model: CreateModel, initialPane: Pane = .photos, onClose: @escaping () -> Void, onPicked: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        self.onPicked = onPicked
        _pane = State(initialValue: initialPane)
    }

    private var isWide: Bool { width >= 600 }
    private var horizontalPadding: CGFloat { isWide ? 32 : 20 }
    private let paneSpacing: CGFloat = 24
    private var showsPhotos: Bool { isWide || pane == .photos }
    private var showsSamples: Bool { isWide || pane == .samples }
    private var samplesWidth: CGFloat { max(0, (width - 2 * horizontalPadding - paneSpacing) * 0.4) }
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        // Deliberately not a ScrollView: the inline picker scrolls out of process, and UIKit
        // cannot arbitrate between its pan and an in-process ancestor's pan across that
        // boundary, so a drag that started on the picker moved neither.
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a photo with a clear subject and good light. It becomes your canvas.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            if !isWide { sourceTabs }
            panes
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 4)
        .padding(.bottom, isWide ? 24 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.paper)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle("New Painting")
        // Nothing scrolls to collapse a large title, and the picker needs the height.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark", action: onClose)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Browse All…", systemImage: "photo.on.rectangle.angled") { isBrowsingAll = true }
                    .help("Browse all photos and albums")
            }
            if cameraAvailable {
                ToolbarItem(placement: .primaryAction) {
                    Button("Take Photo", systemImage: "camera") { isShowingCamera = true }
                }
            }
        }
        .onChange(of: libraryItems) { _, items in
            guard let item = items.first else { return }
            // Clearing the selection lets the same photo be picked again after coming back.
            libraryItems = []
            pick(item)
        }
        .onChange(of: browsedItem) { _, item in
            guard let item else { return }
            browsedItem = nil
            pick(item)
        }
        .photosPicker(isPresented: $isBrowsingAll, selection: $browsedItem, matching: .images, preferredItemEncoding: .current)
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { data in
                model.load(imageData: data)
                onPicked()
            } onFailure: {
                model.fail(.cameraCapture)
                onPicked()
            }
            .ignoresSafeArea()
        }
    }

    private var sourceTabs: some View {
        Picker("Photo Source", selection: $pane) {
            Text("Photos").tag(Pane.photos)
            Text("Samples").tag(Pane.samples)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("photo-source")
    }

    /// One layout for both widths, so the picker keeps its identity (and its loaded grid and
    /// scroll position) across rotation and resizing. On compact widths the samples stack on
    /// top of the hidden picker; they are never an ancestor of it, and it takes no touches.
    private var panes: some View {
        let layout = isWide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: paneSpacing))
            : AnyLayout(ZStackLayout(alignment: .top))
        return layout {
            photosPane
                .opacity(showsPhotos ? 1 : 0)
                .allowsHitTesting(showsPhotos)
                .accessibilityHidden(!showsPhotos)
            if showsSamples {
                samplesPane
                    .frame(width: isWide ? samplesWidth : nil)
            }
        }
    }

    private var photosPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isWide { SectionTitle("Your Photos") }
            // Continuous selection of at most one photo with the selection actions disabled:
            // a tap picks at once, with no Add button to confirm. The shared library gives the
            // items asset identifiers, which the embedded picker needs to show the reset to `[]`
            // as a deselect (so the same photo can be picked again); it needs no authorization,
            // as the picker still runs out of process.
            PhotosPicker(
                selection: $libraryItems, maxSelectionCount: 1, selectionBehavior: .continuous,
                matching: .images, preferredItemEncoding: .current, photoLibrary: .shared()
            ) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
            }
            .photosPickerStyle(.inline)
            .photosPickerDisabledCapabilities(.selectionActions)
            // Only the bottom bar goes: it carries selection status and actions, meaningless
            // when a tap picks. The top bar stays for Photos/Albums, search and the album back button.
            .photosPickerAccessoryVisibility(.hidden, edges: .bottom)
            .accessibilityIdentifier("library-picker")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
            .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var samplesPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isWide { SectionTitle("Samples") }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                    ForEach(Sample.all) { sample in
                        Button {
                            model.load(sample: sample)
                            onPicked()
                        } label: {
                            SampleTile(sample: sample)
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
                // Room for the press scale and hover lift inside the scroll view's clip.
                .padding(4)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Shared by the inline picker and Browse All.
    private func pick(_ item: PhotosPickerItem) {
        model.load(item: item)
        onPicked()
    }
}

private struct SectionTitle: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.rounded(.title3, weight: .bold))
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SampleTile: View {
    let sample: Sample
    @State private var image: CGImage?

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
                Text(sample.title)
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                    }
            }
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
            .accessibilityLabel("Sample: \(sample.title)")
            .accessibilityAddTraits(.isButton)
    }
}
