import CoreGraphics
import Foundation
import PaintCore
import SwiftUI
import Testing
import UIKit
import simd
@testable import PaintByNumber

struct PaintSpeechTests {
    @Test func paletteMetricsFollowDynamicType() {
        #expect(PaletteMetrics(dynamicTypeSize: .large).scale == 1)
        #expect(PaletteMetrics(dynamicTypeSize: .xSmall).scale == 1)
        #expect(PaletteMetrics(dynamicTypeSize: .xLarge).scale == 1.08)
        #expect(PaletteMetrics(dynamicTypeSize: .accessibility1).scale == 1.32)
        #expect(PaletteMetrics(dynamicTypeSize: .accessibility5).scale == 1.4)
        let scales = DynamicTypeSize.allCases.map { PaletteMetrics(dynamicTypeSize: $0).scale }
        #expect(zip(scales, scales.dropFirst()).allSatisfy { $0 <= $1 })
    }

    /// At the default size the palette keeps its original geometry.
    @Test func standardPaletteMetrics() {
        let metrics = PaletteMetrics.standard
        #expect(metrics.pitch == 56)
        #expect(metrics.diameter == 40)
        #expect(metrics.thickness(lines: 1, caption: false) == 76)
        #expect(metrics.thickness(lines: 1, caption: true) == 100)
        for scale: CGFloat in [1, 1.4] {
            let metrics = PaletteMetrics(scale: scale)
            for length: CGFloat in [300, 700, 1000] {
                let lines = metrics.lines(count: 24, length: length, maxLines: 3)
                #expect((1...3).contains(lines))
                if lines < 3 { #expect(metrics.length(count: 24, lines: lines) <= length) }
            }
        }
    }

    /// A nickname goes before the plain name, so VoiceOver gives both ("12, Harbor Fog, dark green").
    @Test func labelsPutTheNicknameBeforeThePlainName() {
        let darkGreen = ColorName(family: .green, lightness: .dark, chroma: .muted)
        #expect(PaintSpeech.colorLabel(number: 12, name: darkGreen, nickname: "Fern Shadow") == "12, Fern Shadow, dark green")
        #expect(PaintSpeech.colorLabel(number: 12, name: darkGreen, nickname: nil) == "12, dark green")
        #expect(PaintSpeech.areaHint(number: 12, name: darkGreen, nickname: "Fern Shadow")
                == "Paints this area with 12, Fern Shadow, dark green.")
        #expect(PaintSpeech.colorFinished(number: 12, name: darkGreen, nickname: "Fern Shadow")
                == "Color 12, Fern Shadow, dark green, finished")
        #expect(PaintSpeech.nextColor(number: 13, name: darkGreen, nickname: "Fern Shadow")
                == "Next color: 13, Fern Shadow, dark green")
        #expect(PaintSpeech.noAreasInView(number: 12, name: darkGreen, nickname: "Fern Shadow")
                == "No areas of 12, Fern Shadow, dark green in view")
    }

    @Test func percentOnlyReachesTheEndsWhenTrue() {
        #expect(PaintSpeech.percent(painted: 0, total: 300) == 0)
        #expect(PaintSpeech.percent(painted: 1, total: 300) == 1)
        #expect(PaintSpeech.percent(painted: 299, total: 300) == 99)
        #expect(PaintSpeech.percent(painted: 300, total: 300) == 100)
        #expect(PaintSpeech.percent(painted: 3, total: 10) == 30)
        #expect(PaintSpeech.percent(painted: 0, total: 0) == 0)
        #expect(PaintSpeech.colorProgress(painted: 10, total: 10) == "finished")
        #expect(PaintSpeech.colorProgress(painted: 3, total: 10) == "30 percent painted")
    }

    @Test func labelsNameNumberAndColor() {
        let darkGreen = ColorName(family: .green, lightness: .dark, chroma: .muted)
        #expect(PaintSpeech.colorLabel(number: 12, name: darkGreen) == "12, dark green")
        #expect(PaintSpeech.areaLabel(number: 12) == "Area 12")
        #expect(PaintSpeech.areaValue(.topLeft) == "not painted, top left")
        #expect(PaintSpeech.areaHint(number: 12, name: darkGreen) == "Paints this area with 12, dark green.")
        #expect(PaintSpeech.colorFinished(number: 12, name: darkGreen) == "Color 12, dark green, finished")
        #expect(PaintSpeech.painted(remaining: 7) == "Painted, 7 left")
        #expect(PaintSpeech.swatchHint(selected: false) == "Selects this color")
        #expect(PaintSpeech.pageScrolled(.topLeft) == "Painting, top left")
    }

    @Test func canvasPositionsInThirds() {
        #expect(CanvasPosition(SIMD2(0, 0), width: 300, height: 300) == .topLeft)
        #expect(CanvasPosition(SIMD2(299, 0), width: 300, height: 300) == .topRight)
        #expect(CanvasPosition(SIMD2(150, 150), width: 300, height: 300) == .center)
        #expect(CanvasPosition(SIMD2(0, 299), width: 300, height: 300) == .bottomLeft)
        #expect(CanvasPosition(SIMD2(299, 299), width: 300, height: 300) == .bottomRight)
        #expect(CanvasPosition(SIMD2(300, 150), width: 300, height: 300) == .right)
        #expect(CanvasPosition(SIMD2(150, 10), width: 0, height: 300) == .topRight)
        #expect(CanvasPosition(SIMD2(.nan, .infinity), width: 300, height: 300) == .center)
        #expect(CanvasPosition.center.spoken == "center")
    }

    /// The app's localizable names read exactly like PaintCore's English ones.
    @Test func colorNameTextMatchesEnglish() {
        for family in ColorName.Family.allCases {
            for lightness in ColorName.Lightness.allCases {
                for chroma in ColorName.Chroma.allCases {
                    let name = ColorName(family: family, lightness: lightness, chroma: chroma)
                    #expect(ColorNameText.string(name) == name.english)
                }
            }
        }
        #expect(ColorNameText.title(ColorName(family: .green, lightness: .dark, chroma: .muted)) == "Dark green")
    }

    /// The color shown on screen: its number, then the nickname when it has one, else the plain name.
    @Test func numberedColorsShowTheNicknameInPlaceOfThePlainName() {
        let darkGreen = ColorName(family: .green, lightness: .dark, chroma: .muted)
        #expect(ColorNameText.numbered(number: 12, name: darkGreen) == "12 · Dark green")
        #expect(ColorNameText.numbered(number: 12, name: darkGreen, nickname: "Fern Shadow") == "12 · Fern Shadow")
    }

    /// Nicknames are English data: any other app language shows the localized structured names.
    @Test func nicknamesAreShownOnlyInEnglish() {
        for code in ["en", "en-GB", "en-US", nil] as [String?] {
            #expect(ColorNameText.nicknamesAvailable(languageCode: code), "\(code ?? "nil")")
        }
        for code in ["de", "fr", "ja", "zh-Hans", "pt-BR", "es-419"] {
            #expect(!ColorNameText.nicknamesAvailable(languageCode: code), "\(code)")
        }
        let palette = (0..<6).map { PaletteColor(oklab: SIMD3(0.2 + Float($0) * 0.12, Float($0 % 2) * 0.05, 0.03), space: .sRGB) }
        let english = ColorNameText.nicknames(for: palette, seed: 9, languageCode: "en")
        #expect(english.count == palette.count && english.allSatisfy { $0 != nil })
        #expect(english == ColorNameText.nicknames(for: palette, seed: 9, languageCode: "en-GB"))
        #expect(ColorNameText.nicknames(for: palette, seed: 9, languageCode: "de") == Array(repeating: nil, count: palette.count))
    }

    /// A color the vocabulary can't name keeps its structured name: it has no nickname to show.
    @Test func colorsWithoutAVocabularyNameHaveNoNickname() {
        let far = PaletteColor(oklab: SIMD3(0.5, 0.6, 0.6), rgb: SIMD3(1, 0, 1))
        #expect(ColorNameText.nicknames(for: [far], seed: 1, languageCode: "en") == [nil])
    }
}

struct CanvasAccessibilityQueryTests {
    /// A 12 × 12 grid of anchors 10 apart on a 120 × 120 canvas; region = row · 12 + column.
    let anchors: [SIMD2<Float>] = (0..<144).map { SIMD2(Float($0 % 12) * 10 + 5, Float($0 / 12) * 10 + 5) }

    @Test func visibleAreasAreTheNearestInReadingOrder() {
        let all = Array(0..<144)
        let center = SIMD2<Float>(60, 60)
        let areas = CanvasAccessibility.visibleAreas(
            all, anchors: anchors, visible: CGRect(x: 0, y: 0, width: 120, height: 120), center: center, rowHeight: 10)
        #expect(areas.count == CanvasAccessibility.limit)
        let distances = all.map { simd_distance_squared(anchors[$0], center) }.sorted()
        let threshold = distances[CanvasAccessibility.limit - 1]
        #expect(areas.allSatisfy { simd_distance_squared(anchors[$0], center) <= threshold })
        let keys = areas.map { CanvasAccessibility.key($0, anchor: anchors[$0], rowHeight: 10) }
        #expect(keys == keys.sorted())
        #expect(Set(areas).count == areas.count)
    }

    @Test func visibleAreasStayInsideTheRect() {
        let visible = CGRect(x: 0, y: 0, width: 50, height: 50)
        let areas = CanvasAccessibility.visibleAreas(
            Array(0..<144), anchors: anchors, visible: visible, center: SIMD2(25, 25), rowHeight: 10)
        #expect(areas.count == 25)
        #expect(areas.allSatisfy { visible.contains(CGPoint(x: CGFloat(anchors[$0].x), y: CGFloat(anchors[$0].y))) })
    }

    @Test func nextWalksInReadingOrderAndWraps() {
        let regions = [14, 2, 30]
        func key(_ r: Int) -> CanvasAccessibility.ReadingKey { CanvasAccessibility.key(r, anchor: anchors[r], rowHeight: 10) }
        #expect(CanvasAccessibility.next(after: nil, in: regions, anchors: anchors, rowHeight: 10) == 2)
        #expect(CanvasAccessibility.next(after: key(2), in: regions, anchors: anchors, rowHeight: 10) == 14)
        #expect(CanvasAccessibility.next(after: key(14), in: regions, anchors: anchors, rowHeight: 10) == 30)
        #expect(CanvasAccessibility.next(after: key(30), in: regions, anchors: anchors, rowHeight: 10) == 2)
        #expect(CanvasAccessibility.next(after: nil, in: [], anchors: anchors, rowHeight: 10) == nil)
    }

    /// Three-finger swipes act like dragging the painting: up shows what is below.
    @Test func pageStepsFollowTheSwipe() {
        let page = CGSize(width: 300, height: 500)
        #expect(CanvasAccessibility.pageStep(.up, page: page) == CGVector(dx: 0, dy: 500))
        #expect(CanvasAccessibility.pageStep(.next, page: page) == CGVector(dx: 0, dy: 500))
        #expect(CanvasAccessibility.pageStep(.down, page: page) == CGVector(dx: 0, dy: -500))
        #expect(CanvasAccessibility.pageStep(.previous, page: page) == CGVector(dx: 0, dy: -500))
        #expect(CanvasAccessibility.pageStep(.left, page: page) == CGVector(dx: 300, dy: 0))
        #expect(CanvasAccessibility.pageStep(.right, page: page) == CGVector(dx: -300, dy: 0))
    }

    @Test func nearestBreaksTiesByLowerIndex() {
        // Regions 0 (5, 5), 1 (15, 5) and 12 (5, 15) are all equally far from (10, 10).
        #expect(CanvasAccessibility.nearest([12, 1], anchors: anchors, to: SIMD2(10, 10)) == 1)
        #expect(CanvasAccessibility.nearest([12, 1, 0], anchors: anchors, to: SIMD2(10, 10)) == 0)
        #expect(CanvasAccessibility.nearest([], anchors: anchors, to: .zero) == nil)
    }
}

@MainActor
struct CanvasViewAccessibilityTests {
    let template = SyntheticTemplate.make(.init(width: 480, height: 640, columns: 6, rows: 8, seed: 3))
    static let chrome = UIEdgeInsets(top: 60, left: 0, bottom: 100, right: 0)

    private func makeCanvas(_ session: PaintingSession, camera: CanvasCamera? = nil) -> CanvasView {
        let canvas = CanvasView(session: session)
        canvas.initialCamera = camera
        canvas.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        canvas.chromeInsets = Self.chrome
        canvas.layoutIfNeeded()
        return canvas
    }

    private func areas(_ canvas: CanvasView) -> [CanvasAreaElement] {
        (canvas.accessibilityElements ?? []).compactMap { $0 as? CanvasAreaElement }
    }

    private func anchor(_ t: Template, _ region: Int) -> SIMD2<Float> { t.anchor(ofRegion: region) }

    private func regions(_ t: Template, ofColor color: Int) -> [Int] {
        t.regions.indices.filter { Int(t.regions[$0].colorIndex) == color }
    }

    @Test func exposesUnpaintedAreasOfTheSelectedColor() throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        let color = try #require(session.selectedColor)
        let elements = areas(canvas)
        #expect((1...CanvasAccessibility.limit).contains(elements.count))
        #expect(elements.count == canvas.accessibilityElements?.count)
        let area = canvas.bounds.inset(by: Self.chrome)
        for element in elements {
            #expect(!session.isPainted(element.region))
            #expect(session.colorOf(element.region) == color)
            #expect(element.accessibilityLabel == "Area \(color + 1)")
            #expect(element.accessibilityValue?.hasPrefix("not painted") == true)
            #expect(element.accessibilityTraits.contains(.button))
            #expect(element.accessibilityIdentifier == "canvas-area-\(element.region)")
            let frame = element.accessibilityFrameInContainerSpace
            let centre = canvas.canvasPoint(forView: CGPoint(x: frame.midX, y: frame.midY))
            #expect(simd_distance(centre, anchor(template, element.region)) < 0.5)
            #expect(min(frame.width, frame.height) >= 44 - 1e-6)
            #expect(area.insetBy(dx: -1e-6, dy: -1e-6).contains(frame))
        }
    }

    @Test func areasAreInReadingOrder() {
        let canvas = makeCanvas(PaintingSession(template: template))
        let elements = areas(canvas)
        let origin = canvas.viewPoint(forCanvas: .zero)
        let zoom = Float(canvas.viewPoint(forCanvas: SIMD2(1, 0)).x - origin.x)
        let keys = elements.map { CanvasAccessibility.key($0.region, anchor: anchor(template, $0.region), rowHeight: 44 / zoom) }
        #expect(keys == keys.sorted())
        for (a, b) in zip(elements, elements.dropFirst()) {
            let fa = a.accessibilityFrameInContainerSpace, fb = b.accessibilityFrameInContainerSpace
            #expect(fb.midY >= fa.midY - 44, "area \(b.region) goes up a row after \(a.region)")
        }
    }

    @Test func busyColorIsCappedToVisibleAreas() throws {
        let t = SyntheticTemplate.make(.init(width: 1800, height: 2400, columns: 48, rows: 64, seed: 11))
        let session = PaintingSession(template: t)
        let color = try #require(t.regionCountsByColor.indices.max { t.regionCountsByColor[$0] < t.regionCountsByColor[$1] })
        session.select(color: color)
        let canvas = makeCanvas(session)
        let area = canvas.bounds.inset(by: Self.chrome)
        let topLeft = canvas.canvasPoint(forView: area.origin)
        let bottomRight = canvas.canvasPoint(forView: CGPoint(x: area.maxX, y: area.maxY))
        let elements = areas(canvas)
        #expect(elements.count == CanvasAccessibility.limit)
        for element in elements {
            let a = anchor(t, element.region)
            #expect(a.x >= topLeft.x && a.x <= bottomRight.x && a.y >= topLeft.y && a.y <= bottomRight.y)
        }
    }

    @Test func activatingAnAreaPaintsIt() throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        let element = try #require(areas(canvas).first)
        let revision = session.revision
        #expect(element.accessibilityActivate())
        #expect(session.isPainted(element.region))
        #expect(session.revision == revision + 1)
        #expect(!areas(canvas).contains { $0.region == element.region })
        // Painting it again is refused.
        #expect(!canvas.paintForAccessibility(element.region))
    }

    @Test func placeholderWhenNothingIsInView() throws {
        let session = PaintingSession(template: template)
        let color = try #require((0..<session.paletteCount).first { regions(template, ofColor: $0).count >= 2 })
        session.select(color: color)
        let own = regions(template, ofColor: color)
        let kept = try #require(own.min { simd_length(anchor(template, $0)) < simd_length(anchor(template, $1)) })
        session.paint(own.filter { $0 != kept }, from: .zero, animated: false)
        let corner = SIMD2(Float(template.width), Float(template.height))
        let canvas = makeCanvas(session, camera: CanvasCamera(zoom: 6, center: corner))
        let elements = try #require(canvas.accessibilityElements as? [NSObject])
        #expect(elements.count == 1)
        let placeholder = try #require(elements.first as? UIAccessibilityElement)
        #expect(!(placeholder is CanvasAreaElement))
        #expect(placeholder.accessibilityIdentifier == "canvas-placeholder")
        #expect(placeholder.accessibilityLabel == "Painting")
        #expect(placeholder.accessibilityValue?.hasPrefix("No areas of \(color + 1), ") == true)
        #expect(placeholder.accessibilityCustomActions?.count == 4)

        session.paint(Array(template.regions.indices), from: .zero, animated: false)
        #expect(session.isComplete)
        let finished = try #require(canvas.accessibilityElements?.first as? UIAccessibilityElement)
        #expect(finished.accessibilityIdentifier == "canvas-placeholder")
        #expect(finished.accessibilityValue == "finished")
    }

    @Test func customActionsAndRotor() throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        let color = try #require(session.selectedColor)
        let elements = areas(canvas)
        try #require(elements.count >= 2)

        let rotor = try #require(canvas.accessibilityCustomRotors?.first)
        #expect(rotor.name == "Unpainted areas")
        let predicate = UIAccessibilityCustomRotorSearchPredicate()
        predicate.currentItem = UIAccessibilityCustomRotorItemResult(targetElement: elements[0], targetRange: nil)
        predicate.searchDirection = .next
        #expect((rotor.itemSearchBlock(predicate)?.targetElement as? CanvasAreaElement) === elements[1])
        predicate.searchDirection = .previous
        #expect(rotor.itemSearchBlock(predicate) == nil)

        let actions = try #require(elements[0].accessibilityCustomActions)
        #expect(actions.map(\.name) == ["Paint next area", "Zoom to next area", "Hint", "Zoom to fit"])
        let remaining = session.remainingByColor[color]
        #expect(actions[0].actionHandler?(actions[0]) == true)
        #expect(session.remainingByColor[color] == remaining - 1)
    }

    @Test func selectionChangeRebuildsElements() throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        let current = try #require(session.selectedColor)
        let other = try #require((0..<session.paletteCount).first { $0 != current && session.remainingByColor[$0] > 0 })
        _ = areas(canvas)
        session.select(color: other)
        let elements = areas(canvas)
        #expect(!elements.isEmpty)
        #expect(elements.allSatisfy { $0.accessibilityLabel == "Area \(other + 1)" && session.colorOf($0.region) == other })
    }

    @Test func hintFocusesTheRevealedArea() throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        canvas.reduceMotion = true
        let color = try #require(session.selectedColor)
        // The session's hint rule: the unpainted region whose number is nearest the view's middle.
        let middle = canvas.visibleCenter
        let hinted = try #require(regions(template, ofColor: color).filter { !session.isPainted($0) }.min { a, b in
            func score(_ r: Int) -> Float {
                template.labels(ofRegion: r).first.map { simd_distance_squared($0.position, middle) } ?? -template.regions[r].area
            }
            return score(a) < score(b)
        })
        canvas.showHint()
        #expect(canvas.pendingFocus == nil, "the settled camera should have consumed the focus request")
        #expect(areas(canvas).contains { $0.region == hinted })
    }

    @Test func pageScrollMovesByTheOfferedBand() throws {
        let session = PaintingSession(template: template)
        let middle = SIMD2(Float(template.width), Float(template.height)) / 2
        let canvas = makeCanvas(session, camera: CanvasCamera(zoom: 4, center: middle))
        canvas.reduceMotion = true
        let origin = canvas.viewPoint(forCanvas: .zero)
        let zoom = Float(canvas.viewPoint(forCanvas: SIMD2(1, 0)).x - origin.x)
        let band = canvas.bounds.inset(by: Self.chrome).insetBy(dx: 22, dy: 22)
        let start = canvas.visibleCenter

        #expect(canvas.accessibilityScroll(.up))
        #expect(canvas.pendingFocus == nil, "the settled camera should have consumed the focus request")
        let down = canvas.visibleCenter
        #expect(abs(down.x - start.x) < 0.01)
        #expect(abs(down.y - start.y - Float(band.height) / zoom) < 0.01)
        let area = canvas.bounds.inset(by: Self.chrome)
        #expect(areas(canvas).allSatisfy { area.contains($0.accessibilityFrameInContainerSpace) })

        #expect(canvas.accessibilityScroll(.down))
        #expect(simd_distance(canvas.visibleCenter, start) < 0.01)

        // Paging stops at the edge, where VoiceOver plays its boundary sound.
        var pages = 0
        while canvas.accessibilityScroll(.left) {
            pages += 1
            try #require(pages < 20)
        }
        #expect(pages >= 1)
        #expect(!canvas.accessibilityScroll(.left))
    }

    @Test func pageScrollAtFitHasNowhereToGo() {
        let canvas = makeCanvas(PaintingSession(template: template))
        canvas.reduceMotion = true
        for direction: UIAccessibilityScrollDirection in [.up, .down, .left, .right, .next, .previous] {
            #expect(!canvas.accessibilityScroll(direction))
        }
    }

    @Test func reduceMotionFillsSettleInstantly() throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        let color = try #require(session.selectedColor)
        let own = regions(template, ofColor: color)
        try #require(own.count >= 2)

        canvas.reduceMotion = true
        session.paint([own[0]], from: anchor(template, own[0]), animated: true)
        let settled = try #require(canvas.regionState(own[0]))
        #expect(settled.start == CanvasClock.never)
        #expect(settled.painted == 1)
        #expect(settled.duration == 0)

        canvas.reduceMotion = false
        session.paint([own[1]], from: anchor(template, own[1]), animated: true)
        let animated = try #require(canvas.regionState(own[1]))
        #expect(animated.start > CanvasClock.never)
        #expect(animated.duration > 0)
    }

    @Test(arguments: [true, false])
    func reduceMotionUndoSettlesInstantly(reduceMotion: Bool) throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        canvas.reduceMotion = reduceMotion
        let color = try #require(session.selectedColor)
        let region = try #require(regions(template, ofColor: color).first)
        session.paint([region], from: anchor(template, region), animated: false)
        #expect(session.undo() == region)
        let state = try #require(canvas.regionState(region))
        #expect(state.painted == 0)
        #expect((state.start == CanvasClock.never) == reduceMotion)
    }

    /// A hint's highlight starts as the camera lands (at once under Reduce Motion, where the
    /// shaders also hold it steady instead of throbbing, as they do for a wrong-paint number).
    @Test(arguments: [true, false])
    func reduceMotionHintLightsUpAtOnce(reduceMotion: Bool) {
        let canvas = makeCanvas(PaintingSession(template: template))
        canvas.reduceMotion = reduceMotion
        canvas.showHint()
        let uniforms = canvas.frameUniforms()
        #expect(uniforms.numbers.w == (reduceMotion ? 1 : 0))
        #expect(uniforms.ids.z >= 0)
        #expect((uniforms.time.z <= uniforms.time.x) == reduceMotion)
    }

    @Test(arguments: [true, false])
    func reduceMotionSkipsTheShine(reduceMotion: Bool) throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        canvas.reduceMotion = reduceMotion
        let color = try #require(session.selectedColor)
        session.paint(regions(template, ofColor: color), from: .zero, animated: true)
        #expect(session.isColorComplete(color))
        #expect((canvas.shineStart == CanvasClock.never) == reduceMotion)
    }

    @Test func reduceMotionReplayStepsWithoutAnimation() async throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        session.paint(Array(template.regions.indices), from: .zero, animated: false)
        canvas.reduceMotion = true
        canvas.replay()
        let painted = Array(template.regions.indices)
        for r in painted {
            let state = try #require(canvas.regionState(r))
            #expect(state.duration == 0 && state.painted == 0)
        }
        try await Task.sleep(for: .seconds(1))
        for r in painted {
            let state = try #require(canvas.regionState(r))
            #expect(state.duration == 0 && state.painted == 1)
        }
    }
}
