import Foundation
import os
import SwiftUI
import TipKit

// The bench's tips of the first version, in the gentle tips' words and rules (the app's design
// panel's design of October 17; the other 17 are in `Features/Tips`). The tip types are
// `nonisolated`: TipKit reads them off the main actor. Their rules are the tips-on parameter and
// the events painting donates (`PaintTips.record`); `TipDesk` decides when one may appear. Tip and
// event ids carry a generation that Settings ▸ Show Tips Again bumps, so tips return at once with
// fresh counts, and the ids of the first version are kept: whoever closed one has it closed.

/// The first painting: how to paint at all. Tap to Paint.
nonisolated struct FirstPaintTip: Tip {
    /// Whether the open painting has paint already. A rule rather than an invalidation, so
    /// the tip still comes back on the next fresh painting after Show Tips Again.
    @Parameter static var hasPaint: Bool = false

    var id: String { PaintTips.scoped("tip.firstPaint") }
    var title: Text { Text("Tap to Paint") }
    var message: Text? { Text("Pick a color below, then tap an area marked with its number to fill it.") }
    var image: Image? { Image(systemName: "hand.tap") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(Self.$hasPaint) { $0 == false }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(PaintTips.swatchTipDisplays) }
    var actions: [Tips.Action] { TipActions.turnOff }
}

/// A minute with no fill while the selected color has areas left: the selected swatch shows where to paint.
nonisolated struct HintTip: Tip {
    var id: String { PaintTips.scoped("tip.hint") }
    var title: Text { Text("Can’t Find It?") }
    var message: Text? { Text("Tap the selected color again, or the lightbulb, to be shown an area to paint.") }
    var image: Image? { Image(systemName: "lightbulb") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.stalls) { $0.donations.count >= 1 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(PaintTips.swatchTipDisplays) }
    var actions: [Tips.Action] { TipActions.turnOff }
}

/// After two taps beside areas too small to hit at this zoom.
nonisolated struct ZoomTip: Tip {
    var id: String { PaintTips.scoped("tip.zoom") }
    var title: Text { Text("Zoom In on Small Areas") }
    var message: Text? { Text("Double-tap the page to zoom in. Pinch to zoom back out.") }
    var image: Image? { Image(systemName: "plus.magnifyingglass") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.smallMisses) { $0.donations.count >= 2 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
    var actions: [Tips.Action] { TipActions.turnOff }
}

/// After 15 single fills: one stroke paints many areas.
nonisolated struct DragPaintTip: Tip {
    var id: String { PaintTips.scoped("tip.dragPaint") }
    var title: Text { Text("Paint Several Areas") }
    var message: Text? { Text("Touch and hold, then drag across areas with this number to fill them in one stroke.") }
    var image: Image? { Image(systemName: "hand.draw") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.singleTaps) { $0.donations.count >= 15 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
    var actions: [Tips.Action] { TipActions.turnOff }
}

/// The first Pencil touch on the page: the Pencil paints while fingers navigate.
nonisolated struct PencilTip: Tip {
    var id: String { PaintTips.scoped("tip.pencil") }
    var title: Text { Text("Paint with Apple Pencil") }
    var message: Text? { Text("The Pencil paints while fingers move the page. Double-tap the Pencil for the next color.") }
    var image: Image? { Image(systemName: "applepencil") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.pencilStrokes) { $0.donations.count >= 1 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
    var actions: [Tips.Action] { TipActions.turnOff }
}

/// Configuration, the answers to the invitation, and the bridge from what the painter does to
/// TipKit donations and invalidations; the desk (`TipDesk`) gives the tips their turns.
enum PaintTips {
    nonisolated static let generationKey = "tipsGeneration"

    nonisolated static func generation(_ defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: generationKey)
    }

    /// `name` in the current generation of tips.
    nonisolated static func scoped(_ name: String, defaults: UserDefaults = .standard) -> String {
        "\(name).\(generation(defaults))"
    }

    /// New tip and event ids: every tip is new again. (`Tips.resetDatastore()` only works
    /// before `Tips.configure`, so it can't serve Settings.)
    static func bumpGeneration(_ defaults: UserDefaults = .standard) {
        defaults.set(generation(defaults) + 1, forKey: generationKey)
    }

    /// Gives the tips their turns. Made after `configure` has cleared a demo's or a test's state.
    static let desk = TipDesk()

    /// Call once at launch. Demo and test runs start from an empty datastore and no answer to the
    /// invitation, so screenshots and tests never depend on what an earlier run saw, donated or
    /// answered; they show no tip but the scenarios' own.
    static func configure() {
        #if DEBUG
        let isolatedRun = DemoMode.isActive || DemoMode.isTestHost
        let demo = DemoMode.scenario.flatMap { demoScenarios[$0] }
        if isolatedRun {
            try? Tips.resetDatastore()
            TipStore().reset()
            TipInvitation.forget()
            if demo == nil { Tips.hideAllTipsForTesting() }
        }
        #endif
        do {
            try Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
        } catch {
            Log.tips.error("TipKit configuration failed: \(String(describing: error), privacy: .public)")
        }
        // Tips are off until the invitation says otherwise: the rules of every tip read this.
        TipSwitch.tipsOn = TipInvitation.isEnabled()
        desk.beginSession()
        #if DEBUG
        // A run that shows a tip lets only that scenario's tips speak.
        desk.isMuted = isolatedRun && demo?.tip == nil
        if let demo {
            if let enabled = demo.enabled { setEnabled(enabled) }
            for id in demo.closed { id.tip.invalidate(reason: .tipClosed) }
        }
        #endif
    }

    // MARK: The answer

    /// Tips on or off: the invitation's answer, the Tips switch in Settings. Either answers the
    /// invitation, which never asks again.
    static func setEnabled(_ enabled: Bool) {
        TipInvitation.record(enabled)
        TipSwitch.tipsOn = enabled
        desk.answered(tipsOn: enabled)
    }

    /// Show Tips or No Thanks, or the note closed (No Thanks).
    static func answerInvitation(showTips: Bool) {
        setEnabled(showTips)
        TipID.invitation.invalidate()
        desk.stop(.invitation)
    }

    /// Turn Off Tips, beneath every hint's close button.
    static func turnOffTips() {
        setEnabled(false)
    }

    /// A button of a tip was tapped. The tips carry the same handlers (`TipActions`,
    /// `InvitationTip`); the views hand this one to TipKit as well, in case it asks for either, and
    /// each answer is the same however many times it is given.
    static func perform(_ action: Tips.Action) {
        switch action.id {
        case "showTips": answerInvitation(showTips: true)
        case "noThanks": answerInvitation(showTips: false)
        case "turnOffTips": turnOffTips()
        default: break
        }
    }

    /// Settings ▸ Show Tips Again: tips on, and every tip as new.
    static func showAgain() {
        bumpGeneration()
        donated.removeAll()
        invalidated.removeAll()
        TipInvitation.record(true)
        TipSwitch.tipsOn = true
        desk.startOver()
        desk.answered(tipsOn: true)
    }

    // MARK: Using a thing

    /// The painter used what `id` is about: the tip never shows, or goes if it does.
    static func used(_ id: TipID) {
        desk.stop(id)
        invalidate(id.tip)
    }

    // MARK: The bench

    /// Tips on the selected swatch move with the selection, and each move presents the popover
    /// anew, which TipKit counts as another display. Using the gesture invalidates them anyway.
    nonisolated static let swatchTipDisplays = 3

    /// What happened while painting, as far as tips are concerned.
    enum Signal: Equatable {
        case tapPainted, strokePainted, strokeEnded, wrongColor, missedSmallArea, hintShown
        case zoomed, pencilUsed
    }

    /// The tip signal of a session event (`isStroking`: a drag or Pencil stroke is under way).
    static func signal(for event: PaintEvent, isStroking: Bool) -> Signal? {
        switch event {
        case .painted: isStroking ? Signal.strokePainted : Signal.tapPainted
        case .strokeEnded: Signal.strokeEnded
        case .rejected: Signal.wrongColor
        case .missedSmallArea: Signal.missedSmallArea
        case .hintShown: Signal.hintShown
        case .colorCompleted, .artworkCompleted, .undone: nil
        }
    }

    static func record(_ signal: Signal) {
        desk.noteActivity()
        switch signal {
        case .tapPainted:
            desk.filled()
            used(.benchTap)
            donate(TipEvents.singleTaps, limit: 20)
        case .strokePainted:
            desk.filled()
            used(.benchTap)
        case .strokeEnded:
            used(.benchDrag)
        case .wrongColor:
            break
        case .missedSmallArea:
            donate(TipEvents.smallMisses, limit: 4)
        case .hintShown:
            used(.benchFind)
        case .zoomed:
            used(.benchZoom)
        case .pencilUsed:
            donate(TipEvents.pencilStrokes, limit: 2)
        }
    }

    /// A painting that already has paint needs no first tip.
    static func paintingOpened(hasProgress: Bool) {
        FirstPaintTip.hasPaint = hasProgress
    }

    // MARK: Donations and invalidations

    /// Donations per event and launch: every rule is met well below its limit, and a painting's
    /// thousands of taps must not grow the datastore.
    private static var donated: [String: Int] = [:]

    /// Donates `event`, up to `limit` times a launch.
    static func donate(_ event: Tips.Event<Tips.EmptyDonation>, limit: Int = 8) {
        let count = donated[event.id, default: 0]
        guard count < limit else { return }
        donated[event.id] = count + 1
        Task { await event.donate() }
    }

    /// Tips invalidated this launch. Strokes report paint per segment, many times a second;
    /// each invalidation is a datastore write, and the first one already settles the tip.
    private static var invalidated: Set<String> = []

    private static func invalidate(_ tip: some Tip) {
        guard invalidated.insert(tip.id).inserted else { return }
        tip.invalidate(reason: .actionPerformed)
    }

    // MARK: Demos

    #if DEBUG
    /// The demo scenarios that show tips (the rest hide every one): the tip each waits for before
    /// it signals readiness, whether it begins with tips on (nil: the invitation is still to be
    /// answered), and the tips already closed when it begins. `paint-tip-fill` is for UI tests.
    private static let demoScenarios: [String: (tip: TipID?, enabled: Bool?, closed: [TipID])] = [
        "paint-tip": (.benchTap, true, []),
        "paint-tip-fill": (.benchTap, true, []),
        "gallery-tips-invitation": (.invitation, nil, []),
        "gallery-tips-invitation-dark": (.invitation, nil, []),
        "gallery-tips-invitation-long-text": (.invitation, nil, []),
        "gallery-tip": (.shelfStarter, true, []),
        "create-tip": (.newPaintingSuggested, true, [.newPaintingDivider]),
        "settings-tips": (nil, true, []),
        "settings-tip": (.drawerWorthALook, true, []),
    ]

    /// The tip the running scenario shows.
    static var demoTip: TipID? { DemoMode.scenario.flatMap { demoScenarios[$0] }?.tip }

    /// Waits until the scenario's tip is up (TipKit presents it a moment after the turn is given).
    static func awaitDemoTip() async {
        guard let expected = demoTip else { return }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(120)
        while desk.turn != expected, clock.now < deadline { try? await Task.sleep(for: .milliseconds(200)) }
        try? await Task.sleep(for: .seconds(1.2))
    }
    #endif
}
