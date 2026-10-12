import Foundation
import SwiftUI

/// One cancellable player for imagesets and v2 atlases, on the contents page and in chapters.
/// A tap restarts the response. Reduce Motion uses still poses; disappearing cancels the loop.
struct MarginariumSpritePlayer: View {
    let pet: MarginariumPet
    let caption: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pose: SpriteFrame?
    @State private var atlas: SpriteAtlas?
    @State private var taps = 0
    @State private var played = 0

    init(pet: MarginariumPet, caption: String) {
        self.pet = pet
        self.caption = caption
        _pose = State(initialValue: pet.animation.idle.first)
    }

    private struct Trigger: Equatable {
        let petID: String
        let taps: Int
        let reduceMotion: Bool
        let ready: Bool
    }

    private var image: Image? {
        switch pose?.source {
        case .asset(let name): Image(name)
        case .cell(let cell): atlas?.image(at: cell).map { Image(decorative: $0, scale: 1) }
        case nil: nil
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            if let image {
                Button {
                    taps += 1
                } label: {
                    image.resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 104)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(caption))
                .accessibilityHint(Text(pet.hint))
                .accessibilityIdentifier("marginarium-pet-\(pet.id)")
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // The button already reads the description; keep it readable if art fails.
                .accessibilityHidden(image != nil)
        }
        .frame(maxWidth: .infinity)
        .task(id: pet.id) {
            pose = pet.animation.idle.first
            atlas = nil
            if case .atlas(let url) = pet.art {
                let loaded = await SpriteAtlasCache.shared.load(at: url)
                guard !Task.isCancelled else { return }
                atlas = loaded
            }
        }
        .task(id: Trigger(petID: pet.id, taps: taps, reduceMotion: reduceMotion, ready: image != nil)) {
            await animate()
        }
        // Lazy reader rows can retain their State after scrolling off screen.
        .onDisappear { atlas = nil }
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
