import PhotosUI
import SwiftUI
import UIKit

/// First step of the create flow: the photo library inline, the camera, and samples.
struct PhotoSourceView: View {
    let model: CreateModel
    var onClose: () -> Void
    var onPicked: () -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var width: CGFloat = 0

    private var isWide: Bool { width >= 600 }
    private var sampleColumns: Int { width >= 1100 ? 4 : isWide ? 3 : 2 }
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Choose a photo with a clear subject and good light. It becomes your canvas.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Your Photos")
                    PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .current) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                    }
                    .photosPickerStyle(.inline)
                    .photosPickerDisabledCapabilities(.selectionActions)
                    .photosPickerAccessoryVisibility(.hidden, edges: .all)
                    .frame(height: isWide ? 380 : 300)
                    .background(Theme.surface)
                    .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 0.5)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Samples")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: sampleColumns), spacing: 14) {
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
                }
            }
            .padding(.horizontal, isWide ? 32 : 20)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .background(Theme.paper)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle("New Painting")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark", action: onClose)
            }
            if cameraAvailable {
                ToolbarItem(placement: .primaryAction) {
                    Button("Take Photo", systemImage: "camera") { isShowingCamera = true }
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            model.load(item: item)
            onPicked()
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { data in
                model.load(imageData: data)
                onPicked()
            }
            .ignoresSafeArea()
        }
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
            .task {
                let loaded = await SampleImages.shared.load(sample, maxPixelSize: 640)
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sample: \(sample.title)")
            .accessibilityAddTraits(.isButton)
    }
}
