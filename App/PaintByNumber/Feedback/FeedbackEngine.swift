import Foundation
import PaintCore

/// Turns painting events into haptics and sound. One shared instance; attach each
/// `PaintingSession` when its screen appears.
///
/// Preferences (read live, set from Settings): `hapticsEnabled`, `soundsEnabled` (both
/// default on).
final class FeedbackEngine {
    static let shared = FeedbackEngine()

    enum Keys {
        static let haptics = "hapticsEnabled"
        static let sounds = "soundsEnabled"
    }

    private let haptics = HapticsPlayer()
    private let sounds = SoundPlayer()

    /// How long the canvas animates a fill, so the haptic swell can match it. The canvas may
    /// update this per paint.
    var fillDuration: TimeInterval = 0.4

    private var hapticsEnabled: Bool { UserDefaults.standard.object(forKey: Keys.haptics) as? Bool ?? true }
    private var soundsEnabled: Bool { UserDefaults.standard.object(forKey: Keys.sounds) as? Bool ?? true }

    private init() {}

    /// Warms up the haptic and audio engines so the first stroke isn't late.
    func prepare() {
        if hapticsEnabled { haptics.prepare() }
        if soundsEnabled { sounds.prepare() }
    }

    func attach(to session: PaintingSession) {
        session.onEvent { [weak self, weak session] event in
            guard let self, let session else { return }
            self.handle(event, in: session)
        }
    }

    /// Selection changes and other UI detents.
    func selectionChanged() {
        if hapticsEnabled { haptics.tick() }
    }

    private func handle(_ event: PaintEvent, in session: PaintingSession) {
        let haptic = hapticsEnabled, sound = soundsEnabled
        switch event {
        case let .painted(regions, color):
            // Perceived size of what was painted, relative to the canvas.
            let area = regions.reduce(Float(0)) { $0 + session.template.regions[$1].area }
            let canvas = Float(max(1, session.template.width * session.template.height))
            let size = min(1, (area / canvas).squareRoot() * 6)
            if haptic { haptics.paint(strength: size, duration: fillDuration) }
            if sound { sounds.paint(color: color, velocity: 0.35 + 0.65 * size) }
        case .rejected:
            if haptic { haptics.reject() }
            if sound { sounds.reject() }
        case let .colorCompleted(color):
            if haptic { haptics.colorComplete() }
            if sound { sounds.colorComplete(color: color) }
        case .artworkCompleted:
            if haptic { haptics.celebrate() }
            if sound { sounds.celebrate() }
        case .undone:
            if haptic { haptics.tick() }
        case .strokeEnded:
            break
        }
    }
}
