#if UNRELEASED
import CoreGraphics
import Foundation
import Metal
import PaintCore
import QuartzCore
import UIKit
import os
import simd

/// The cave's whole screen (painting-company row 371): a `CAMetalLayer` drawn every frame by a
/// display link, the touches handed to its `CaveScene`. Each bay's maps are made off the main
/// thread as the camera nears it (`CaveBay`) and held by the renderer until another bay needs its
/// slot; the painting being blown sends only the rectangle of pigment that changed each frame.
///
/// VoiceOver finds one element, the wall, which allows direct interaction (a finger on it blows
/// and carries the torch as for anyone), says what is in hand and how far the painting has come,
/// and offers what a hand can do there as custom actions: take up a pigment, blow the next area,
/// leave your hand, draw a new painting, walk deeper or toward the daylight, leave the cave.
final class CaveWallView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    let scene: CaveScene
    private var renderer: CaveRenderer?
    private var displayLink: CADisplayLink?
    private var last: CFTimeInterval?
    /// Each bay's key as held by the renderer, and as being made.
    private var held: [Int: String] = [:]
    private var making: [Int: String] = [:]
    /// Every bay on screen is held: the wall is showing (a demo waits for it).
    private(set) var isShowingWall = false

    private static var context: CaveRenderContext?

    init(scene: CaveScene) {
        self.scene = scene
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .black
        isOpaque = true
        if let layer = layer as? CAMetalLayer {
            layer.pixelFormat = CaveRenderContext.format
            layer.framebufferOnly = true
            layer.isOpaque = true
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        }
        isAccessibilityElement = true
        accessibilityTraits = .allowsDirectInteraction
        accessibilityLabel = String(localized: "cave.wall", defaultValue: "Cave wall",
                                    comment: "VoiceOver label of the cave mode's whole screen: a rock wall lit by a torch")
        Task { await prepare() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func prepare() async {
        if Self.context == nil { Self.context = await CaveRenderContext.make() }
        guard let context = Self.context else { return }
        do {
            renderer = try CaveRenderer(context: context)
        } catch {
            Log.canvas.error("The cave's renderer failed: \(String(describing: error), privacy: .public)")
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let layer = layer as? CAMetalLayer else { return }
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        scene.layOut(size: SIMD2(Float(bounds.width), Float(bounds.height)))
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if displayLink == nil {
                let link = CADisplayLink(target: CaveLinkTarget(self), selector: #selector(CaveLinkTarget.tick(_:)))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
            scene.sound.start()
        } else {
            displayLink?.invalidate()
            displayLink = nil
            last = nil
            scene.save()
            scene.sound.stop()
        }
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = last.map { Float(now - $0) } ?? 0
        last = now
        scene.step(dt)
        guard let renderer, let layer = layer as? CAMetalLayer else { return }
        hold(renderer)
        if let change = scene.takePigmentChanges(), held[change.bay] != nil {
            renderer.paint(bay: change.bay, rgba: change.rgba, minX: change.minX, minY: change.minY, width: change.width, height: change.height)
        }
        let size = layer.drawableSize
        renderer.draw(in: layer, uniforms: scene.uniforms(drawable: SIMD2(Float(size.width), Float(size.height))), sprites: scene.sprites())
    }

    /// Makes the bays the camera needs and hands each to the renderer as it is ready.
    private func hold(_ renderer: CaveRenderer) {
        let wanted = scene.wantedBays
        var showing = true
        for index in wanted {
            guard let bay = scene.bay(index) else { continue }
            if held[index] == bay.key { continue }
            showing = false
            if making[index] == bay.key { continue }
            making[index] = bay.key
            let content = bay.content, tools = bay.tools, key = bay.key
            Task {
                let (maps, half) = await Background.run { () -> (CaveBay.Maps, [Float16]) in
                    let maps = CaveBay.maps(index: index, content: content, tools: tools)
                    return (maps, CaveRenderer.halfRelief(maps))
                }
                guard self.making[index] == key else { return }
                self.making[index] = nil
                // Still wanted, as it was asked for.
                guard self.scene.bay(index)?.key == key, let renderer = self.renderer else { return }
                for other in self.held.keys where other != index && other % CaveShader.slots == index % CaveShader.slots {
                    self.held[other] = nil
                }
                renderer.hold(maps, relief: half)
                renderer.paint(bay: index, rgba: self.scene.pigment(of: index))
                self.held[index] = key
            }
        }
        isShowingWall = showing
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            scene.touchBegan(ObjectIdentifier(touch), at: SIMD2(Float(p.x), Float(p.y)), width: Float(touch.majorRadius) * 2)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            scene.touchMoved(ObjectIdentifier(touch), to: SIMD2(Float(p.x), Float(p.y)))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { scene.touchEnded(ObjectIdentifier(touch)) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { scene.touchEnded(ObjectIdentifier(touch)) }
    }

    // MARK: - VoiceOver

    static func name(of pigment: CavePigment) -> String {
        switch pigment {
        case .charcoal: String(localized: "cave.pigment.charcoal", defaultValue: "Charcoal", comment: "A cave painting pigment: charcoal, black")
        case .manganese: String(localized: "cave.pigment.manganese", defaultValue: "Manganese", comment: "A cave painting pigment: manganese, a dark brown earth")
        case .redOchre: String(localized: "cave.pigment.redOchre", defaultValue: "Red ochre", comment: "A cave painting pigment: red ochre, a red earth")
        case .yellowOchre: String(localized: "cave.pigment.yellowOchre", defaultValue: "Yellow ochre", comment: "A cave painting pigment: yellow ochre, a yellow earth")
        }
    }

    override var accessibilityValue: String? {
        get {
            if scene.isWaitingForHand {
                return String(localized: "cave.value.hand", defaultValue: "Finished. The rock above it waits for your hand.",
                              comment: "VoiceOver value of the cave wall once a painting is finished: lay four or five fingers on the rock to leave a hand stencil")
            }
            if let progress = scene.progressText {
                let pigment = Self.name(of: scene.pigmentInHand)
                return String(localized: "cave.value.painting", defaultValue: "\(pigment) in hand. Areas blown: \(progress.done) of \(progress.of)",
                              comment: "VoiceOver value of the cave wall while a painting is blown: the pigment in hand, then the areas done of all its areas")
            }
            return String(localized: "cave.value.bare", defaultValue: "Bare rock, and a lump of charcoal to draw with",
                          comment: "VoiceOver value of the cave wall at bare rock, where a new painting is drawn")
        }
        set { _ = newValue }
    }

    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            var actions: [UIAccessibilityCustomAction] = []
            if scene.hasPigments && !scene.isWaitingForHand {
                for pigment in CavePigment.allCases where pigment != scene.pigmentInHand {
                    let name = Self.name(of: pigment)
                    actions.append(UIAccessibilityCustomAction(name: String(localized: "cave.action.take", defaultValue: "Take up \(name)",
                                                                            comment: "VoiceOver action in the cave: take up a pigment from its hollow on the ledge; the pigment's name")) { [weak self] _ in
                        self?.scene.pick(pigment)
                        return true
                    })
                }
                actions.append(UIAccessibilityCustomAction(name: String(localized: "cave.action.blow", defaultValue: "Blow pigment",
                                                                        comment: "VoiceOver action in the cave: blow pigment over the next area of the painting")) { [weak self] _ in
                    self?.scene.blowNextArea() ?? false
                })
            }
            if scene.isWaitingForHand {
                actions.append(UIAccessibilityCustomAction(name: String(localized: "cave.action.hand", defaultValue: "Leave your hand",
                                                                        comment: "VoiceOver action in the cave: leave a hand stencil beside the finished painting")) { [weak self] _ in
                    self?.scene.leaveHand()
                    return true
                })
            }
            if scene.isAtBareRock {
                actions.append(UIAccessibilityCustomAction(name: String(localized: "cave.action.draw", defaultValue: "Draw a new painting",
                                                                        comment: "VoiceOver action in the cave: choose a photo to draw on the bare rock")) { [weak self] _ in
                    self?.scene.onChoosePhoto?()
                    return true
                })
            }
            if !scene.isAtEnd {
                actions.append(UIAccessibilityCustomAction(name: String(localized: "cave.action.deeper", defaultValue: "Walk deeper",
                                                                        comment: "VoiceOver action in the cave: walk further along the wall, away from the daylight")) { [weak self] _ in
                    self?.scene.walk(1)
                    return true
                })
            }
            if !scene.isAtMouth {
                actions.append(UIAccessibilityCustomAction(name: String(localized: "cave.action.daylight", defaultValue: "Walk toward the daylight",
                                                                        comment: "VoiceOver action in the cave: walk back along the wall toward the cave's mouth")) { [weak self] _ in
                    self?.scene.walk(-1)
                    return true
                })
            }
            actions.append(UIAccessibilityCustomAction(name: String(localized: "cave.action.leave", defaultValue: "Leave the cave",
                                                                    comment: "VoiceOver action in the cave: walk out into the daylight, back to the app")) { [weak self] _ in
                self?.scene.leave()
                return true
            })
            return actions
        }
        set { _ = newValue }
    }
}

/// Breaks the display link → view retain cycle.
private final class CaveLinkTarget: NSObject {
    weak var view: CaveWallView?

    init(_ view: CaveWallView) { self.view = view }

    @objc func tick(_ link: CADisplayLink) { view?.tick(link) }
}
#endif
