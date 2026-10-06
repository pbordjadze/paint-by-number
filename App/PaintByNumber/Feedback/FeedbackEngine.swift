import Foundation
import PaintCore

/// Turns painting events into haptics and sound. One shared instance; attach each
/// `PaintingSession` when its screen appears.
///
/// Preferences (read live, set from Settings): `SettingsKey.haptics`, `SettingsKey.sounds`
/// (both default on).
final class FeedbackEngine {
    static let shared = FeedbackEngine()

    private let haptics = HapticsPlayer()
    private let sounds = SoundPlayer()

    private final class AttachedSession {
        weak var session: PaintingSession?
        init(_ session: PaintingSession) { self.session = session }
    }

    /// Weak, not by `ObjectIdentifier`: a freed session's address can come back as a new one's.
    private var attached: [AttachedSession] = []

    /// How long the canvas animates a fill, so the haptic swell can match it. The canvas may
    /// update this per paint.
    var fillDuration: TimeInterval = 0.4

    private var hapticsEnabled: Bool { UserDefaults.standard.object(forKey: SettingsKey.haptics) as? Bool ?? true }
    private var soundsEnabled: Bool { UserDefaults.standard.object(forKey: SettingsKey.sounds) as? Bool ?? true }

    private init() {}

    /// Plays a session's events, once however often its screen appears, and warms up the
    /// engines so the first stroke isn't late.
    func attach(to session: PaintingSession) {
        attached.removeAll { $0.session == nil }
        guard !attached.contains(where: { $0.session === session }) else { return }
        attached.append(AttachedSession(session))
        session.onEvent { [weak self, weak session] event in
            guard let self, let session else { return }
            self.handle(event, in: session)
        }
        prepare()
    }

    private func prepare() {
        if hapticsEnabled { haptics.prepare() }
        if soundsEnabled { sounds.prepare() }
    }

    /// Selection changes and other UI detents.
    func selectionChanged() {
        if hapticsEnabled { haptics.tick() }
    }

    private func handle(_ event: PaintEvent, in session: PaintingSession) {
        let hapticsOn = hapticsEnabled, soundsOn = soundsEnabled
        switch event {
        case let .painted(regions, _):
            // Perceived size of what was painted, relative to the canvas.
            let area = regions.reduce(Float(0)) { $0 + session.template.regions[$1].area }
            let canvas = Float(max(1, session.template.width * session.template.height))
            let size = min(1, (area / canvas).squareRoot() * 6)
            if hapticsOn { haptics.paint(strength: size, duration: fillDuration) }
            if soundsOn { sounds.paint(velocity: 0.35 + 0.65 * size) }
        case .rejected:
            if hapticsOn { haptics.reject() }
            if soundsOn { sounds.reject() }
        case .colorCompleted:
            if hapticsOn { haptics.colorComplete() }
            if soundsOn { sounds.colorComplete() }
        case .artworkCompleted:
            if hapticsOn { haptics.celebrate() }
            if soundsOn { sounds.celebrate() }
        case .undone:
            if hapticsOn { haptics.tick() }
        case .strokeEnded, .hintShown, .missedSmallArea:
            // A near miss follows the rejected buzz already felt; the hint moves the camera.
            break
        }
    }
}
