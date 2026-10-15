import CoreGraphics
import Foundation
import SwiftUI

/// One cancellable player for imagesets and v2 atlases, on the contents page and in chapters.
/// A tap restarts the response. Reduce Motion uses still poses; disappearing cancels the loop.
/// Beside a margin note it is small, captionless and hidden from VoiceOver: the note already
/// names its speaker, so the pet is only company for sighted readers. There it also waves when
/// its note's words are opened (`greeting`), as it does on the contents page when tapped.
struct MarginariumSpritePlayer: View {
    let pet: MarginariumPet
    /// Nil beside a margin note.
    let caption: String?
    /// False for a page's picture that the page's title names: the caption is its VoiceOver label alone.
    private let showsCaption: Bool
    private let width: CGFloat
    /// Each new nonzero value plays the tap response, as does a nonzero one on appearing.
    private let greeting: Int
    /// `marginarium-pet-<id>` unless a page shows the same pet twice.
    private let identifier: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var pose: SpriteFrame?
    /// The cells it plays, each a bitmap of its own at the size it draws (`SpriteAtlasCache`): never
    /// the 14 MiB sheet, which a page of twenty drawings could not hold.
    @State private var frames: [SpriteAtlas.Cell: CGImage] = [:]
    @State private var taps = 0
    @State private var played = 0

    init(pet: MarginariumPet, caption: String, width: CGFloat = 120, identifier: String? = nil) {
        self.init(pet: pet, caption: caption, showsCaption: true, width: width, greeting: 0, identifier: identifier)
    }

    /// A page's picture under a title that names it: `label` is for VoiceOver alone.
    init(pet: MarginariumPet, label: String, width: CGFloat) {
        self.init(pet: pet, caption: label, showsCaption: false, width: width, greeting: 0, identifier: nil)
    }

    init(pet: MarginariumPet, marginWidth: CGFloat, greeting: Int = 0) {
        self.init(pet: pet, caption: nil, showsCaption: false, width: marginWidth, greeting: greeting, identifier: nil)
    }

    private init(pet: MarginariumPet, caption: String?, showsCaption: Bool, width: CGFloat, greeting: Int,
                 identifier: String?) {
        self.pet = pet
        self.caption = caption
        self.showsCaption = showsCaption
        self.width = width
        self.greeting = greeting
        self.identifier = identifier ?? "marginarium-pet-\(pet.id)"
        _pose = State(initialValue: pet.animation.idle.first)
    }

    /// The cells are 192 × 208.
    private var height: CGFloat { width * 104 / 96 }

    private struct Trigger: Equatable {
        let petID: String
        let taps: Int
        let reduceMotion: Bool
        let ready: Bool
    }

    private var image: Image? {
        switch pose?.source {
        case .asset(let name): Image(name)
        case .cell(let cell): frames[cell].map { Image(decorative: $0, scale: 1) }
        case nil: nil
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            if let image {
                if let caption {
                    button(image)
                        .accessibilityLabel(Text(caption))
                        .accessibilityHint(Text(pet.hint))
                } else {
                    button(image).accessibilityHidden(true)
                }
            } else if caption == nil || !showsCaption {
                // The slot stays, so a note doesn't change shape when its pet's sheet arrives.
                Color.clear.frame(width: width, height: height)
            }
            if let caption, showsCaption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    // The button already reads the description; keep it readable if art fails.
                    .accessibilityHidden(image != nil)
            }
        }
        .frame(maxWidth: caption == nil ? nil : CGFloat.infinity)
        .task(id: pet.id) {
            pose = pet.animation.idle.first
            frames = [:]
            guard case .atlas(let url) = pet.art else { return }
            let pixels = Int((height * displayScale).rounded(.up))
            let loaded = await SpriteAtlasCache.shared.frames(at: url, maxPixelSize: pixels)
            guard !Task.isCancelled else { return }
            frames = loaded ?? [:]
        }
        .task(id: Trigger(petID: pet.id, taps: taps, reduceMotion: reduceMotion, ready: image != nil)) {
            await animate()
        }
        .onChange(of: greeting, initial: true) { _, greeting in
            if greeting > 0 { taps += 1 }
        }
        // Lazy reader rows can retain their State after scrolling off screen.
        .onDisappear { frames = [:] }
    }

    private func button(_ image: Image) -> some View {
        Button {
            taps += 1
        } label: {
            // A brief's picture draws a 192 × 208 cell at up to three times its pixels.
            image.resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: width, height: height)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func animate() async {
        let animation = pet.animation
        let responds = taps > played
        played = taps
        guard image != nil, !animation.idle.isEmpty else { return }
        do {
            if responds {
                for step in animation.actionFrames(reduceMotion: reduceMotion) {
                    try Task.checkCancellation()
                    pose = step
                    try await Task.sleep(for: step.hold)
                }
            }
            if reduceMotion {
                pose = animation.idle.first
                return
            }
            while true {
                for step in animation.idle {
                    try Task.checkCancellation()
                    pose = step
                    try await Task.sleep(for: step.hold)
                }
            }
        } catch {
            // Cancellation leaves the next run (or nothing, after dismissal) in charge.
        }
    }
}
