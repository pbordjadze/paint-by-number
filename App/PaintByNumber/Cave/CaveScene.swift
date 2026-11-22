#if UNRELEASED
import Foundation
import PaintCore
import simd

/// What happens in the cave (painting-company row 371), frame by frame, with no drawing of its own:
/// `CaveWallView` hands it the touches and draws what it says. The wall is one long row of bays
/// (`CaveWall`): the mouth, each painting oldest first, then bare rock; the bay being worked
/// holds the painter's things on its ledge. The camera is the wall point at the screen's left.
///
/// - The torch, wedged in a crack, is carried by a finger; held near either side of the screen it
///   walks you along the wall. The way out is the era's Settings (`CaveEra`), as in every era.
/// - A tap on a hollow takes up its pigment; a finger held on the rock blows it there, the spray
///   widening the longer it is held. Pigment lands where it belongs (`CavePigmentLayer`).
/// - Once every area is done the torch flares, and a few grains of ochre gather above the
///   painting; four or five fingers pressed together leave the hand's stencil, and the painting
///   is done. Bare rock comes next, with a lump of charcoal: a tap on it chooses the next photo.
@MainActor
final class CaveScene {
    nonisolated struct Painting: Sendable {
        let id: UUID
        let plan: CavePlan
        var progress: CaveProgress
        /// Its pigment as saved (`CavePigmentLayer.rgba()`), nil for none yet.
        var pigment: [UInt8]?
        /// Its name in the gallery and on its screen.
        var title: String = ""
        /// Bumped by each save of the shelf, for the gallery's card to draw its picture again.
        var revision = 0

        var isComplete: Bool { !progress.done.contains(false) && progress.hand != nil }
    }

    /// What a bay is: its content and tools, and a key that changes whenever its maps would.
    struct Bay: Equatable {
        var content: CaveBay.Content
        var tools: CaveBay.Tools
        var key: String
    }

    private(set) var paintings: [Painting]
    /// The painting being blown (the newest, while it isn't complete), as its pigment.
    private(set) var layer: CavePigmentLayer?

    // MARK: The view

    /// The screen's size in points.
    var viewSize = SIMD2<Float>(393, 852) {
        didSet { clampCamera() }
    }
    /// Screen points per wall point: the wall fills the screen's height.
    var scale: Float { max(0.1, viewSize.y / Float(CaveWall.height)) }
    var visibleWidth: Float { viewSize.x / scale }
    private(set) var camera: Float = 0
    private var cameraTarget: Float = 0
    var reduceMotion = false

    // MARK: The world

    private(set) var time: Float = 0
    private(set) var torch = SIMD2<Float>(360, 500)
    private var torchRest = SIMD2<Float>(360, 500)
    private(set) var flicker: Float = 0.9
    private(set) var pigmentInHand: CavePigment = .redOchre
    /// When the painting was finished (its flare), and when a new drawing appeared on the rock.
    private var finishedAt: Float?
    private var drawnAt: Float?
    private var hand: (hand: CaveHand, amount: Float)?

    private enum Grip {
        /// The torch, held this far from the finger (wall points), the finger where it is on screen.
        case torch(offset: SIMD2<Float>, finger: SIMD2<Float>)
        /// Pigment blown at a wall point since a moment.
        case blow(at: SIMD2<Float>, since: Float)
        /// A touch of a hand being laid flat, or of nothing.
        case none
    }

    private var grips: [ObjectIdentifier: Grip] = [:]
    private var touches: [ObjectIdentifier: (screen: SIMD2<Float>, width: Float, since: Float)] = [:]

    private struct Mote {
        var p: SIMD2<Float>
        var v: SIMD2<Float>
        var life: Float
        var pigment: CavePigment
        var r: Float
    }

    private var dust: [Mote] = []
    private var sparks: [Mote] = []
    private var unsaved = false
    /// Pigment blown since the last save, short of finishing an area: kept every few seconds.
    private var pigmentLanded = false
    private var lastSave: Float = 0

    // MARK: What the scene asks of the app

    /// A painting's progress and pigment to keep.
    var onSave: ((UUID, CaveProgress, [UInt8]) -> Void)?
    /// The lump of charcoal was tapped: choose the next photo.
    var onChoosePhoto: (() -> Void)?
    let sound: CaveSound
    private let defaults: UserDefaults

    static let cameraKey = "cave.camera"

    /// One painting on its own, as the frame's painting screen shows it (painting-company row
    /// 379): its bay between plain rock, the camera still on it, no mouth, no walking.
    let isSingle: Bool
    /// The one painting's bay: deep enough that the widest screen, centred on it, shows only
    /// plain rock either side, never the mouth's carving (bay 0) or the wall's start.
    static let singleBay = 3

    init(paintings: [Painting], sound: CaveSound, single: Bool = false, defaults: UserDefaults = .standard) {
        self.paintings = paintings
        self.sound = sound
        self.isSingle = single
        self.defaults = defaults
        if !single, let saved = defaults.object(forKey: Self.cameraKey) as? Double {
            camera = Float(saved)
        }
        cameraTarget = camera
        makeLayer()
        placeTorch()
    }

    // MARK: - The wall's layout

    /// The bay being worked: the newest painting while it isn't complete, else the bare rock past it.
    var activeBay: Int {
        if isSingle { return Self.singleBay }
        guard let last = paintings.last else { return 1 }
        return last.isComplete ? paintings.count + 1 : paintings.count
    }

    /// The far end of the cave: a little past the bay after the one being worked, into the dark.
    var end: Float { isSingle ? Float(8 * CaveWall.bayWidth) : Float((activeBay + 1) * CaveWall.bayWidth + 150) }

    /// The bay at `index`, or nil past the cave's end.
    func bay(_ index: Int) -> Bay? {
        if isSingle {
            guard index >= 0, index <= 2 * Self.singleBay else { return nil }
            guard index == Self.singleBay, let p = paintings.first else { return Bay(content: .bare, tools: .none, key: "rock-\(index)") }
            let tools: CaveBay.Tools = p.isComplete ? .none : .pigments
            return Bay(content: .painting(p.plan), tools: tools, key: "\(p.id)-\(tools == .pigments)")
        }
        guard index >= 0, index <= activeBay + 1 else { return nil }
        if index == 0 { return Bay(content: .mouth, tools: .none, key: "mouth") }
        if index <= paintings.count {
            let p = paintings[index - 1]
            let tools: CaveBay.Tools = index == activeBay ? .pigments : .none
            return Bay(content: .painting(p.plan), tools: tools, key: "\(p.id)-\(tools == .pigments)")
        }
        let tools: CaveBay.Tools = index == activeBay ? .charcoal : .none
        return Bay(content: .bare, tools: tools, key: "bare-\(index)-\(tools == .charcoal)")
    }

    /// The bays worth holding: those on screen and one more either side, as many as the
    /// renderer has slots for (`CaveShader.slots`), the margins given up first, so no two share one.
    var wantedBays: [Int] {
        let onScreenFirst = Int((camera / Float(CaveWall.bayWidth)).rounded(.down))
        let onScreenLast = Int(((camera + visibleWidth) / Float(CaveWall.bayWidth)).rounded(.down))
        var first = max(0, onScreenFirst - 1)
        var last = max(first, min(onScreenLast + 1, isSingle ? 2 * Self.singleBay : activeBay + 1))
        while last - first + 1 > CaveShader.slots {
            if last > onScreenLast { last -= 1 } else if first < onScreenFirst { first += 1 } else { last -= 1 }
        }
        return Array(first...last)
    }

    /// A painting's pigment for its bay, as saved, or the layer's.
    func pigment(of bay: Int) -> [UInt8]? {
        if isSingle {
            guard bay == activeBay else { return nil }
            return layer?.rgba() ?? paintings.first?.pigment
        }
        guard bay >= 1, bay <= paintings.count else { return nil }
        if bay == activeBay, let layer { return layer.rgba() }
        return paintings[bay - 1].pigment
    }

    /// The layer's changes since the last call, as a rectangle of RGBA8 in the active bay.
    func takePigmentChanges() -> (bay: Int, rgba: [UInt8], minX: Int, minY: Int, width: Int, height: Int)? {
        guard layer != nil, let c = layer?.takeChanges(), let layer else { return nil }
        let rgba = layer.rgba(minX: c.minX, minY: c.minY, maxX: c.maxX, maxY: c.maxY)
        return (activeBay, rgba, c.minX, c.minY, c.maxX - c.minX + 1, c.maxY - c.minY + 1)
    }

    /// The paintings as the shelf has them now: a new one is the next painting, its bay's drawing
    /// appearing with a flare.
    func update(_ paintings: [Painting]) {
        guard paintings.map(\.id) != self.paintings.map(\.id) else { return }
        let grew = paintings.count > self.paintings.count
        save()
        self.paintings = paintings
        finishedAt = nil
        hand = nil
        makeLayer()
        if grew { drawnAt = time }
    }

    private func makeLayer() {
        guard let last = paintings.last, !last.isComplete else {
            layer = nil
            return
        }
        var layer = CavePigmentLayer(plan: last.plan)
        layer.restore(rgba: last.pigment, progress: last.progress)
        _ = layer.takeChanges()
        self.layer = layer
        if layer.isFinished { finishedAt = time - 10 }
        // The pigment in hand: the first still wanted.
        if let a = layer.nextArea(of: nil) { pigmentInHand = last.plan.pigments[a - 1] }
    }

    // MARK: - Touches

    func screenToWall(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(p.x / scale + camera, p.y / scale) }

    func touchBegan(_ id: ObjectIdentifier, at screen: SIMD2<Float>, width: Float) {
        touches[id] = (screen, width / scale, time)
        let p = screenToWall(screen)
        if startHandIfLaid() { return }
        let local = p - SIMD2(Float(activeBay * CaveWall.bayWidth), 0)
        if layer != nil, let cup = CaveWall.cup(at: local) {
            pick(cup)
            grips[id] = Grip.none
            return
        }
        if !isSingle, layer == nil, ((local - CaveWall.charcoal) / SIMD2(30, 24)).caveLengthSquared < 1 {
            grips[id] = Grip.none
            onChoosePhoto?()
            return
        }
        if (p - (torch + SIMD2(0, 30))).caveLengthSquared < 48 * 48 {
            grips[id] = .torch(offset: torch - p, finger: screen)
            sound.lift()
            return
        }
        grips[id] = .blow(at: p, since: time)
        sound.blow(true)
    }

    func touchMoved(_ id: ObjectIdentifier, to screen: SIMD2<Float>) {
        touches[id]?.screen = screen
        switch grips[id] {
        case .some(.torch(let offset, _)): grips[id] = .torch(offset: offset, finger: screen)
        case .some(.blow(_, let since)): grips[id] = .blow(at: screenToWall(screen), since: since)
        default: break
        }
    }

    func touchEnded(_ id: ObjectIdentifier) {
        touches[id] = nil
        let grip = grips.removeValue(forKey: id)
        if case .some(.torch) = grip, !isSingle {
            defaults.set(Double(cameraTarget), forKey: Self.cameraKey)
        }
        if !grips.values.contains(where: { if case .blow = $0 { true } else { false } }) { sound.blow(false) }
    }

    /// Four or five fingers down at once, on a finished painting waiting for its hand: lays it.
    private func startHandIfLaid() -> Bool {
        guard let layer, layer.isFinished, layer.hand == nil, hand == nil, touches.count >= 4 else { return false }
        // Fingers that came down together, within half a second.
        let recent = touches.values.filter { time - $0.since < 0.5 }
        guard recent.count >= 4 else { return false }
        let bayX = Float(activeBay * CaveWall.bayWidth)
        let tips = recent.prefix(5).map { screenToWall($0.screen) - SIMD2(bayX, 0) }
        let widths = recent.prefix(5).map { min(14, max(6, $0.width * 0.8)) }
        layHand(CaveHand(fingers: Array(tips), widths: Array(widths)))
        for key in grips.keys { grips[key] = Grip.none }
        sound.blow(false)
        return true
    }

    private func layHand(_ h: CaveHand) {
        hand = (h, 0)
        sound.blow(true)
    }

    // MARK: - What VoiceOver and the demos do

    func pick(_ pigment: CavePigment) {
        pigmentInHand = pigment
        let cup = CaveWall.cups[Int(pigment.rawValue)].centre + SIMD2(Float(activeBay * CaveWall.bayWidth), -6)
        puff(at: cup, pigment: pigment, count: 18)
        sound.pick()
    }

    /// Blows the next area wanted of the pigment in hand (or of any, taking it up), all of it.
    @discardableResult
    func blowNextArea() -> Bool {
        guard let a = layer?.nextArea(of: pigmentInHand), let pigment = layer?.plan.pigments[a - 1],
              let points = layer?.points(of: a) else { return false }
        if pigment != pigmentInHand { pick(pigment) }
        var finished: [Int] = []
        // Mutated in place (`layer?.`): a copy would duplicate the bay's pigment on every call.
        for (k, p) in points.enumerated() where k % 9 == 0 {
            finished += layer?.blow(at: p, radius: 10, amount: 0.5, pigment: pigment) ?? []
            if k % 90 == 0 { puff(at: p + SIMD2(Float(activeBay * CaveWall.bayWidth), 0), pigment: pigment, count: 1) }
        }
        pigmentLanded = true
        areasDone(finished)
        return true
    }

    /// Leaves a spread hand above the finished painting.
    func leaveHand() {
        guard let layer, layer.isFinished, layer.hand == nil, hand == nil else { return }
        layHand(CaveHand.spread(at: CaveWall.handSpot))
    }

    /// Walks a bay deeper (1) or toward the daylight (-1), the torch carried along.
    func walk(_ bays: Int) {
        guard !isSingle else { return }
        cameraTarget += Float(bays * CaveWall.bayWidth)
        clampCamera()
        torchRest.x = cameraTarget + visibleWidth * 0.5
        defaults.set(Double(cameraTarget), forKey: Self.cameraKey)
    }

    var isAtMouth: Bool { isSingle || camera < Float(CaveWall.bayWidth) * 0.5 }
    var isAtEnd: Bool { isSingle || cameraTarget >= maxCamera - 1 }

    #if DEBUG
    // MARK: - The demos' painter

    private static let demoFinger = NSObject()

    /// A finger held on the rock, blowing there, as if for a second and a half already.
    func demoHold(at p: SIMD2<Float>) {
        grips[ObjectIdentifier(Self.demoFinger)] = .blow(at: p, since: time - 1.5)
        sound.blow(true)
    }

    /// The camera on a bay's middle, the torch beside the painting.
    func demoLook(at bay: Int) {
        cameraTarget = Float(bay * CaveWall.bayWidth + CaveWall.bayWidth / 2) - visibleWidth / 2
        clampCamera()
        camera = cameraTarget
        torchRest = SIMD2(Float(bay * CaveWall.bayWidth) + 360, 430)
        torch = torchRest
    }
    #endif

    // MARK: - A frame

    func step(_ dt: Float) {
        let dt = min(dt, 0.05)
        time += dt
        // The torch, carried: near either side of the screen it walks you along the wall.
        for grip in grips.values {
            guard case .torch(let offset, let finger) = grip else { continue }
            let side = finger.x / max(1, viewSize.x)
            if isSingle {
                // One painting: the torch goes where the finger takes it, and the wall stays.
            } else if side < 0.15 { cameraTarget -= 320 * dt * (0.15 - side) / 0.15 }
            if side > 0.85 { cameraTarget += 320 * dt * (side - 0.85) / 0.15 }
            clampCamera()
            let at = screenToWall(finger) + offset
            torchRest = SIMD2(min(max(at.x, 14), end), min(max(at.y, 40), CaveWall.ledge - 30))
        }
        camera += (cameraTarget - camera) * min(1, dt / 0.18)
        torch += (torchRest - torch) * min(1, dt / 0.04)
        if reduceMotion {
            flicker = 0.92
        } else {
            let t = time
            flicker = 0.86 + 0.07 * sin(t * 11) + 0.05 * sin(t * 29 + 2) + 0.04 * sin(t * 67 + 5) + 0.03 * (Float.random(in: 0..<1) - 0.5)
            if Float.random(in: 0..<1) < dt / 0.09 {
                sparks.append(Mote(p: torch + SIMD2(Float.random(in: -3...3), 10), v: SIMD2(Float.random(in: -6...6), -30 - Float.random(in: 0..<30)),
                                   life: 1, pigment: .redOchre, r: 0.6))
            }
        }
        sound.place(torch: torch, listener: SIMD2(camera + visibleWidth / 2, Float(CaveWall.height) / 2))
        blow(dt)
        if var h = hand, layer != nil {
            h.amount = min(1, h.amount + dt / 2.2)
            layer?.stencil(h.hand, amount: h.amount)
            hand = h
            if h.amount >= 1 {
                hand = nil
                sound.blow(false)
                sound.settle()
                save()
            }
        }
        layer?.settle(seconds: dt)
        for k in dust.indices {
            dust[k].p += dust[k].v * dt
            dust[k].v.y += 20 * dt
            dust[k].life -= dt / 1.4
        }
        dust.removeAll { $0.life <= 0 }
        for k in sparks.indices {
            sparks[k].p += sparks[k].v * dt
            sparks[k].life -= dt / 0.9
        }
        sparks.removeAll { $0.life <= 0 }
        if (unsaved && time - lastSave > 1) || (pigmentLanded && time - lastSave > 4) { save() }
    }

    private func blow(_ dt: Float) {
        let bayX = Float(activeBay * CaveWall.bayWidth)
        var finished: [Int] = []
        for grip in grips.values {
            guard case .blow(let p, let since) = grip else { continue }
            let radius = 9 + min(14, (time - since) * 10)
            if let f = layer?.blow(at: p - SIMD2(bayX, 0), radius: radius, amount: 0.055 * dt * 60, pigment: pigmentInHand) {
                finished += f
                pigmentLanded = true
            }
            if Float.random(in: 0..<1) < 0.8 * dt * 60 {
                puff(at: p + SIMD2(Float.random(in: -0.5...0.5), Float.random(in: -0.5...0.5)) * radius, pigment: pigmentInHand, count: 1)
            }
        }
        areasDone(finished)
    }

    private func areasDone(_ finished: [Int]) {
        guard !finished.isEmpty else { return }
        unsaved = true
        sound.settle()
        if let layer, layer.isFinished, finishedAt == nil {
            finishedAt = time
            sound.finish()
            save()
        }
    }

    private func puff(at p: SIMD2<Float>, pigment: CavePigment, count: Int) {
        for _ in 0..<count where dust.count < 400 {
            dust.append(Mote(p: p, v: SIMD2(Float.random(in: -15...15), -10 - Float.random(in: 0..<30)), life: 1, pigment: pigment,
                             r: 1 + Float.random(in: 0..<2)))
        }
    }

    /// Keeps the active painting's progress and pigment.
    func save() {
        lastSave = time
        unsaved = false
        pigmentLanded = false
        // A hand still being blown is finished first: once saved, the painting is complete for good.
        if let h = hand, layer != nil {
            layer?.stencil(h.hand, amount: 1)
            hand = nil
            sound.blow(false)
            sound.settle()
        }
        guard let layer, let last = paintings.last, !last.isComplete else { return }
        let progress = layer.progress
        let rgba = layer.rgba()
        paintings[paintings.count - 1].progress = progress
        paintings[paintings.count - 1].pigment = rgba
        onSave?(last.id, progress, rgba)
        // A hand laid: the painting is complete, and bare rock is next.
        if progress.hand != nil {
            self.layer = nil
            finishedAt = nil
        }
    }

    // MARK: - The camera

    var maxCamera: Float { max(0, end - visibleWidth) }

    private func clampCamera() {
        if isSingle {
            // The painting's bay in the middle of the screen.
            cameraTarget = Float(CaveWall.bayWidth) * (Float(Self.singleBay) + 0.5) - visibleWidth / 2
            camera = cameraTarget
            return
        }
        cameraTarget = min(max(cameraTarget, 0), maxCamera)
        camera = min(max(camera, -50), maxCamera + 50)
    }

    private func placeTorch() {
        clampCamera()
        camera = cameraTarget
        torchRest = SIMD2(camera + min(visibleWidth - 40, 360), 500)
        torch = torchRest
    }

    /// Lays the scene out for a screen: called when the view's size is first known.
    func layOut(size: SIMD2<Float>) {
        let first = viewSize != size
        viewSize = size
        if first { placeTorch() }
    }

    // MARK: - What the renderer draws

    var flare: Float {
        guard !reduceMotion else { return 0 }
        let since = [finishedAt, drawnAt].compactMap { $0 }.map { time - $0 }.filter { $0 >= 0 }.min()
        guard let since else { return 0 }
        return max(0, sin(min(1, since / 2.4) * .pi))
    }

    func uniforms(drawable: SIMD2<Float>) -> CaveUniforms {
        let pxPerPoint = drawable.y / Float(CaveWall.height)
        let lampOn: Float = activeBay >= 1 && (!isSingle || layer != nil) ? 1 : 0
        // One painting on its own is deep in the cave: no daylight reaches it.
        let mouth = isSingle ? SIMD2<Float>(-20_000, -20_000) : CaveWall.mouth
        let lamp = CaveWall.lampFlame + SIMD2(Float(activeBay * CaveWall.bayWidth), -6)
        return CaveUniforms(
            view: SIMD4(drawable.x, drawable.y, pxPerPoint, camera),
            torch: SIMD4(torch.x, torch.y + 10, 64, flicker),
            lamp: SIMD4(lamp.x, lamp.y, 30, lampOn),
            mouth: SIMD4(mouth.x, mouth.y, flare, 0),
            misc: SIMD4(time, end, CaveBay.reliefDepth, reduceMotion ? 1 : 0),
            slotsA: SIMD4(repeating: -1), slotsB: SIMD4(repeating: -1))
    }

    func sprites() -> [CaveSprite] {
        var out: [CaveSprite] = []
        out.reserveCapacity(64 + dust.count + sparks.count)
        let t = reduceMotion ? 0 : time
        let tx = torch.x, ty = torch.y
        // The torch: three sticks bound together, wedged in the rock, and its charred head.
        let pivot = SIMD2(tx, ty + 34), turn: Float = -0.28
        func turned(_ v: SIMD2<Float>) -> SIMD2<Float> { SIMD2(v.x * cos(turn) - v.y * sin(turn), v.x * sin(turn) + v.y * cos(turn)) }
        let sticks: [(dx: Float, width: Float, length: Float, color: SIMD3<Float>)] = [
            (-3.2, 3.2, 60, SIMD3(0.23, 0.14, 0.08)), (2.8, 3.4, 56, SIMD3(0.18, 0.11, 0.06)), (0, 3.6, 64, SIMD3(0.29, 0.18, 0.09)),
        ]
        for (dx, width, length, color) in sticks {
            let head = SIMD2(dx, -12), foot = SIMD2(dx * 0.4, length)
            let mid = pivot + turned((head + foot) / 2)
            let along = turned((foot - head) / 2)
            let across = turned(SIMD2(width / 2, 0))
            var stick = CaveSprite(.stick, at: mid, radii: SIMD2(1, 1), inner: SIMD4(color, 1))
            stick.place = SIMD4(mid.x, mid.y, across.x, across.y)
            stick.axis = SIMD4(along.x, along.y, CaveSprite.Kind.stick.rawValue, 0)
            out.append(stick)
        }
        out.append(CaveSprite(.dot, at: pivot + turned(SIMD2(0, -12)), radii: SIMD2(7, 5), angle: turn, inner: SIMD4(0.07, 0.04, 0.02, 1)))
        // Smoke, rising and drifting.
        for k in 0..<6 {
            let phase = (t * 0.35 + Float(k) / 6).truncatingRemainder(dividingBy: 1)
            let p = SIMD2(tx + sin(t + Float(k)) * 6 * phase + 8 * phase, ty + 6 - phase * 120)
            out.append(CaveSprite(.dot, at: p, radii: SIMD2(repeating: 6 + phase * 18), inner: SIMD4(0.055, 0.04, 0.03, 0.07 * (1 - phase))))
        }
        // The flame and its glow.
        let fy = ty + 22, fl = 1 + 0.25 * sin(t * 21) + 0.15 * sin(t * 47 + 1)
        let glow = 70 * flicker * (1 + flare * 0.6)
        out.append(CaveSprite(.glow, at: SIMD2(tx, fy - 6), radii: SIMD2(glow, glow), inner: SIMD4(1, 0.67, 0.31, 0.35), outer: SIMD4(1, 0.47, 0.16, 0)))
        for k in 0..<5 {
            let sway = sin(t * 13 + Float(k) * 2) * 3.5 * fl + Float(k - 2) * 2.2
            let tier = Float(k % 3)
            let stretch = 0.8 + 0.4 * abs(sin(t * 20 + Float(k)))
            let inner = k == 2 ? SIMD4<Float>(1, 0.98, 0.86, 0.9) : SIMD4<Float>(1, 0.78, 0.43, 0.7)
            out.append(CaveSprite(.glow, at: SIMD2(tx + sway * 0.5, fy - 12 - tier * 3),
                                  radii: SIMD2((8 - tier * 2) * fl, (22 - tier * 5) * fl * stretch), angle: sway * 0.05,
                                  inner: inner, outer: SIMD4(0.78, 0.24, 0.04, 0)))
        }
        // The fat lamp's flame, by the tools.
        if activeBay >= 1, !isSingle || layer != nil {
            let lamp = CaveWall.lampFlame + SIMD2(Float(activeBay * CaveWall.bayWidth), 0)
            let lf = 1 + 0.12 * sin(t * 17) + 0.08 * sin(t * 41)
            out.append(CaveSprite(.glow, at: lamp, radii: SIMD2(30, 30), inner: SIMD4(1, 0.59, 0.24, 0.22), outer: SIMD4(1, 0.47, 0.16, 0)))
            out.append(CaveSprite(.glow, at: lamp + SIMD2(0, -1), radii: SIMD2(2.8 * lf, 7.5 * lf), angle: 0.15,
                                  inner: SIMD4(1, 0.84, 0.59, 0.95), outer: SIMD4(0.78, 0.24, 0.04, 0)))
        }
        for s in sparks {
            out.append(CaveSprite(.glow, at: s.p, radii: SIMD2(repeating: 1.1), inner: SIMD4(1, (150 + 80 * s.life) / 255, 0.27, s.life)))
        }
        // Pigment in the air, lit by the torch.
        for d in dust {
            let lit = 1 / (1 + (d.p - torch).caveLengthSquared / 40_000)
            let c = d.pigment.rgb * SIMD3(1.6, 1.4, 1.2)
            out.append(CaveSprite(.glow, at: d.p, radii: SIMD2(repeating: d.r), inner: SIMD4(c, d.life * 0.5 * lit)))
        }
        // A finished painting: a hand's worth of bare rock waits, a few grains of ochre round it.
        if let finishedAt, let layer, layer.hand == nil, hand == nil {
            let a = min(1, (time - finishedAt - 2.6) / 2.5)
            if a > 0 {
                let pulse = reduceMotion ? 1 : 0.7 + 0.3 * sin(time * 2)
                let at = SIMD2(Float(activeBay * CaveWall.bayWidth), 0)
                for g in Self.grains {
                    out.append(CaveSprite(.dot, at: g + at, radii: SIMD2(repeating: 1.1), inner: SIMD4(0.48, 0.16, 0.08, 0.5 * a * pulse)))
                }
            }
        }
        return out
    }

    private static let grains = CaveHand.grains(at: CaveWall.handSpot)

    // MARK: - What VoiceOver says

    /// The pigments on the ledge, when a painting is being blown.
    var hasPigments: Bool { layer != nil }
    var isWaitingForHand: Bool { layer?.isFinished == true && layer?.hand == nil && hand == nil }
    var isAtBareRock: Bool { layer == nil && !isSingle }
    var progressText: (done: Int, of: Int)? { layer.map { ($0.doneCount, $0.plan.areaCount) } }
}

extension SIMD2 where Scalar == Float {
    /// The square of its length.
    var caveLengthSquared: Float { x * x + y * y }
}
#endif
