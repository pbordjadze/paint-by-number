import CoreGraphics
import Foundation
import SwiftUI

/// One cancellable player for imagesets and v2 atlases, on the contents page and in chapters.
/// A tap restarts the response. Reduce Motion uses still poses; disappearing cancels the loop.
/// Beside a margin note it is small, captionless and hidden from VoiceOver: the note already
/// names its speaker, so the pet is only company for sighted readers. There it also waves when
/// its note's words are opened (`greeting`).
struct MarginariumSpritePlayer: View {
    let pet: MarginariumPet
    /// Nil beside a margin note.
    let caption: String?
    private let width: CGFloat
    /// Each new nonzero value plays the tap response, as does a nonzero one on appearing.
    private let greeting: Int
    /// `marginarium-pet-<id>` unless a page shows the same pet twice.
    private let identifier: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var pose: SpriteFrame?
    @State private var atlas: SpriteAtlas?
    /// A margin player's cells, redrawn small, in place of `atlas`: a page of notes by several
    /// guardians must not keep a 14 MiB decoded sheet alive for each.
    @State private var thumbnails: [SpriteAtlas.Cell: CGImage] = [:]
    @State private var taps = 0
    @State private var played = 0

    init(pet: MarginariumPet, caption: String, width: CGFloat = 120, identifier: String? = nil) {
        self.init(pet: pet, caption: caption, width: width, greeting: 0, identifier: identifier)
    }

    init(pet: MarginariumPet, marginWidth: CGFloat, greeting: Int = 0) {
        self.init(pet: pet, caption: nil, width: marginWidth, greeting: greeting, identifier: nil)
    }

    private init(pet: MarginariumPet, caption: String?, width: CGFloat, greeting: Int, identifier: String?) {
        self.pet = pet
        self.caption = caption
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
        case .cell(let cell): (thumbnails[cell] ?? atlas?.image(at: cell)).map { Image(decorative: $0, scale: 1) }
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
            } else if caption == nil {
                // The slot stays, so a note doesn't change shape when its pet's sheet arrives.
                Color.clear.frame(width: width, height: height)
            }
            if let caption {
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
            atlas = nil
            thumbnails = [:]
            if case .atlas(let url) = pet.art {
                let loaded = await SpriteAtlasCache.shared.load(at: url)
                guard !Task.isCancelled else { return }
                if caption == nil, let loaded {
                    let pixels = Int((height * displayScale).rounded(.up))
                    let cells = await Background.run { loaded.thumbnails(maxPixelSize: pixels) }
                    guard !Task.isCancelled else { return }
                    thumbnails = cells
                } else {
                    atlas = loaded
                }
            }
        }
        .task(id: Trigger(petID: pet.id, taps: taps, reduceMotion: reduceMotion, ready: image != nil)) {
            await animate()
        }
        .onChange(of: greeting, initial: true) { _, greeting in
            if greeting > 0 { taps += 1 }
        }
        // Lazy reader rows can retain their State after scrolling off screen.
        .onDisappear {
            atlas = nil
            thumbnails = [:]
        }
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
