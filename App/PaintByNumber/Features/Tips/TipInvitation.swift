import Foundation

/// The invitation's answer, and the Tips switch in Settings, are one thing: `SettingsKey.tipsEnabled`.
/// Unset until the first visit to the shelf is answered (Show Tips, No Thanks, or the note closed,
/// which counts as No Thanks); set, the invitation never shows again, whatever changes the value.
nonisolated enum TipInvitation {
    enum Answer: Equatable, Sendable {
        case unanswered, showTips, noThanks
    }

    static func answer(in defaults: UserDefaults = .standard) -> Answer {
        guard let enabled = defaults.object(forKey: SettingsKey.tipsEnabled) as? Bool else { return .unanswered }
        return enabled ? .showTips : .noThanks
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        answer(in: defaults) == .showTips
    }

    static func record(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: SettingsKey.tipsEnabled)
    }

    /// Unanswered again: what a demo or test launch starts from.
    static func forget(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: SettingsKey.tipsEnabled)
    }
}

/// Which tips a moment may offer, in the order the design meets them. A pure choice from what the
/// screen and the painter's history say; the desk (`TipDesk`) then asks TipKit which of them is
/// eligible (its events and parameters) and the pacing whether it may appear now.
nonisolated enum TipMoments {
    /// The shelf (the gallery) as the tips see it.
    struct Shelf: Equatable, Sendable {
        var artworks = 0
        var started = 0
        var ready = 0
        var finished = 0
        /// Pages still being prepared: the starters of the first launch.
        var preparing = false
    }

    /// What the shelf may say on this visit. Nothing before its pages are in view; the invitation
    /// until it is answered; after Show Tips, the page that waits, then, as the painter reaches
    /// them, the rest. At most one of them is given its turn per visit (`TipDesk`).
    static func shelf(
        _ facts: Shelf, answer: TipInvitation.Answer, history: TipHistory, now: Date, calendar: Calendar = .current
    ) -> [TipID] {
        guard !facts.preparing, facts.artworks > 0 else { return [] }
        switch answer {
        case .unanswered: return [.invitation]
        case .noThanks: return []
        case .showTips: break
        }
        var due: [TipID] = []
        // Nobody has painted: the starters wait, and no painting has been opened.
        if facts.started == 0, facts.finished == 0, facts.ready > 0, history.openedCount == 0 {
            due.append(.shelfStarter)
        }
        if facts.started + facts.finished > 0 { due.append(.shelfNewPainting) }
        if facts.artworks >= 2, history.isDayTwoOrLater(now: now, calendar: calendar) { due.append(.shelfHold) }
        if facts.finished > 0 { due += [.shelfSettings, .shelfTimeLapse] }
        return due
    }

    /// What the preview may say once its template is final, given whether the divider's tip is
    /// over (Already Chosen for You waits for it) and where the settings came from.
    static func preview(dividerIsOver: Bool, isSuggested: Bool, canRefine: Bool) -> [TipID] {
        var due: [TipID] = [.newPaintingDivider]
        if dividerIsOver, isSuggested { due.append(.newPaintingSuggested) }
        due.append(.newPaintingSliders)
        if canRefine { due.append(.newPaintingRefine) }
        return due
    }
}
