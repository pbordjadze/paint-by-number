#if UNRELEASED
import CoreGraphics
import PaintCore
import Ravenna
import SwiftUI

/// The Frame, the era behind 1000 on the year wheel (painting-company row 379; SideStore and
/// Debug builds): the frame every mode shares (`ModeShell`) with nothing of a mode's own in it,
/// so the frame's rules can be seen. What a mode would supply (its gallery's cards, its canvas,
/// its paints) is an empty place, named. A picture picked opens on a painting screen and is kept
/// nowhere.
struct FrameEra: View {
    let leave: (Int) -> Void

    @State private var path: [FramePicture] = []

    var body: some View {
        ModeShell(look: Self.look, path: $path, leave: leave, opensSettings: Self.opensSettings, make: openPicture) { _ in
            ModeSlot(name: Text("The mode’s gallery"))
                .padding(20)
        } destination: { picture in
            ModePaintingFrame(title: picture.title, opening: .open, cantOpen: Text("Can’t Open Painting")) {
                VStack(spacing: 12) {
                    ModeSlot(name: Text("The mode’s canvas"), picture: picture.image)
                    ModeSlot(name: Text("The mode’s paints"))
                        .frame(height: 96)
                }
                .padding(16)
            }
        }
        #if DEBUG
        .task { await demo() }
        #endif
    }

    /// The Frame in itself: its look is the frame's plainest, a pale grey accent on near black.
    static var look: ModeLook {
        ModeLook(year: EraYear.frame, title: Text("The Frame"), newTitle: Text("New Painting"), accent: Color(white: 0.82),
                 backdrop: Color(red: 0.11, green: 0.11, blue: 0.13), id: "frame")
    }

    /// Whether the launch asked for one of The Frame's demo scenarios (`-demo frame-<name>`),
    /// which open the era whatever the clock says (Debug builds only).
    static var isDemoScenario: Bool {
        #if DEBUG
        return DemoMode.scenario?.hasPrefix("frame-") == true
        #else
        return false
        #endif
    }

    private static var opensSettings: Bool {
        #if DEBUG
        return DemoMode.scenario == "frame-settings"
        #else
        return false
        #endif
    }

    private func openPicture(_ picked: ModePicture) async {
        guard let image = picked.cgImage else { return }
        let title = picked.sample?.title
            ?? String(localized: "frame.photo", defaultValue: "Your Photo",
                      comment: "The Frame (a hidden mode that is only the frame every mode shares): the name of a painting started from the painter's own photo")
        path.append(FramePicture(title: title, image: image))
    }

    #if DEBUG
    /// `frame-gallery`: the gallery's place, empty; `frame-settings`: its Settings, the Year
    /// row; `frame-painting`: a library picture opened on the painting screen.
    private func demo() async {
        switch DemoMode.scenario {
        case "frame-gallery", "frame-settings":
            try? await Task.sleep(for: .seconds(1))
            DemoMode.markReady()
        case "frame-painting":
            guard let sample = Sample.starters.first, let url = sample.url,
                  let photo = try? await Background.run({ try PhotoLoader.load(url: url, maxPixelSize: 1200) })
            else { return }
            await openPicture(ModePicture(photo: photo, sample: sample))
            try? await Task.sleep(for: .seconds(1.5))
            DemoMode.markReady()
        default:
            break
        }
    }
    #endif
}

/// A picture opened in The Frame, equal by its own id.
struct FramePicture: Hashable {
    let id = UUID()
    let title: String
    let image: CGImage

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A place in the frame that a mode fills: an outline, dashed, with its name, and the picture
/// faintly under it where there is one.
struct ModeSlot: View {
    let name: Text
    var picture: CGImage?

    var body: some View {
        ZStack {
            if let picture {
                Image(decorative: picture, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.22)
                    .accessibilityHidden(true)
            }
            name
                .font(.display(.title3))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
