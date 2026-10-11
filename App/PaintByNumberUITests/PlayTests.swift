#if DEBUG
import CoreGraphics
import Foundation
import UIKit
import XCTest

/// The simulator host's mailbox consumer. UI operations stay on MainActor; the async loop
/// yields between polls so the self-test can act as a host in the same runner.
final class PlayTests: XCTestCase {
    func testMailboxMoveValidation() throws {
        let valid = [
            #"{"do":"fill","area":1}"#, #"{"do":"tap","label":"Paint 1"}"#,
            #"{"do":"drag","from":{"x":20,"y":30},"to":{"x":80,"y":60},"steps":12}"#,
            #"{"do":"wait","seconds":0}"#, #"{"do":"screenshot"}"#,
        ]
        for json in valid {
            do { _ = try PlayMove(data: Data(json.utf8)) }
            catch { XCTFail("\(json): \(error)") }
        }
        let invalid = [
            #"[]"#, #"{"do":"unknown"}"#, #"{"do":"screenshot","extra":0}"#,
            #"{"do":"fill"}"#, #"{"do":"fill","area":true}"#, #"{"do":"fill","area":0}"#,
            #"{"do":"fill","area":1.5}"#, #"{"do":"tap","label":""}"#,
            #"{"do":"fill","area":1.0}"#, #"{"do":"fill","area":1e0}"#,
            #"{"do":"tap","label":"   "}"#,
            #"{"do":"wait","seconds":-0.2}"#, #"{"do":"wait","seconds":"0.2"}"#,
            #"{"do":"wait","seconds":1e999}"#,
            #"{"do":"drag","from":{"x":0,"y":0,"z":0},"to":{"x":1,"y":1},"steps":1}"#,
            #"{"do":"drag","from":{"x":0,"y":0},"to":{"x":1,"y":1},"steps":0}"#,
        ]
        for json in invalid {
            do {
                _ = try PlayMove(data: Data(json.utf8))
                XCTFail("Accepted invalid move: \(json)")
            } catch {}
        }
    }

    @MainActor
    func testMailbox() async throws {
        guard let path = ProcessInfo.processInfo.environment["PLAY_MAILBOX"], !path.isEmpty else {
            throw XCTSkip("PLAY_MAILBOX is unset")
        }
        guard path.hasPrefix("/") else { throw PlayFailure("PLAY_MAILBOX must be an absolute path") }
        let mailbox = URL(fileURLWithPath: path, isDirectory: true)
        try requireFreshMailbox(mailbox)
        let app = try await launchPainting()
        // No idle deadline or move limit: the host ends this test with SIGINT.
        try await runMailbox(mailbox, app: app)
    }

    @MainActor
    func testMailboxSelfTest() async throws {
        let mailbox = FileManager.default.temporaryDirectory.appending(path: "play-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mailbox, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: mailbox) }
        let app = try await launchPainting()
        // Start the real consumer in a task while this test supplies one outstanding move.
        // XCUITest interaction must remain on MainActor even in that task.
        let loop = Task { @MainActor in
            try await self.runMailbox(mailbox, app: app, moveLimit: 3, idleTimeout: 30)
        }
        defer { loop.cancel() }
        let hello = try await response("hello.json", in: mailbox)
        XCTAssertEqual(Set(hello.keys), ["version", "state"])
        XCTAssertEqual(hello["version"] as? Int, 1)
        let initial = try state(in: hello)
        XCTAssertEqual(initial.screen, "painting")
        XCTAssertNotNil(initial.selectedPaint)
        XCTAssertTrue(initial.filledAreas.isEmpty)
        XCTAssertGreaterThanOrEqual(initial.areaCount, 2)

        let moves: [[String: Any]] = [
            ["do": "fill", "area": 1], ["do": "wait", "seconds": 0.2], ["do": "fill", "area": 2],
        ]
        var states: [PlayState] = []
        for (index, move) in moves.enumerated() {
            let number = index + 1
            try PlayWire.publish(move, named: "move-\(number).json", in: mailbox)
            let done = try await response("done-\(number).json", in: mailbox, errorNumber: number)
            XCTAssertEqual(Set(done.keys), ["state"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: mailbox.appending(path: "error-\(number).json").path))
            states.append(try state(in: done))
        }
        try await loop.value
        XCTAssertEqual(states[0].filledAreas, [1])
        XCTAssertEqual(states[1], states[0], "Waiting changed the painting")
        XCTAssertEqual(states[2].filledAreas, [1, 2])
        for state in states {
            XCTAssertEqual(state.screen, "painting")
            XCTAssertEqual(state.areaCount, initial.areaCount)
            XCTAssertNotNil(state.selectedPaint)
        }
    }

    /// Invalid moves get exactly one error and consume their sequence number; the next
    /// valid move still uses the shared consumer. No app interaction on validation failure.
    @MainActor
    func testMailboxRejectsInvalidMove() async throws {
        let mailbox = FileManager.default.temporaryDirectory.appending(path: "play-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mailbox, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: mailbox) }
        let app = try await launchPainting()
        let loop = Task { @MainActor in
            try await self.runMailbox(mailbox, app: app, moveLimit: 2, idleTimeout: 30)
        }
        defer { loop.cancel() }
        let initial = try state(in: await response("hello.json", in: mailbox))
        try PlayWire.publish(["do": "fill", "area": 1, "extra": true], named: "move-1.json", in: mailbox)
        let error = try await response("error-1.json", in: mailbox)
        XCTAssertEqual(Set(error.keys), ["reason"])
        XCTAssertFalse((error["reason"] as? String ?? "").isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mailbox.appending(path: "done-1.json").path))
        try PlayWire.publish(["do": "screenshot"], named: "move-2.json", in: mailbox)
        let after = try state(in: await response("done-2.json", in: mailbox, errorNumber: 2))
        try await loop.value
        XCTAssertEqual(after, initial)
    }

    @MainActor
    private func launchPainting() async throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-open", "-playHarness"]
        app.launch()
        guard app.buttons["Close"].waitForExistence(timeout: 90) else {
            throw PlayFailure("The demo painting did not open")
        }
        guard app.descendants(matching: .any)["play-state"].waitForExistence(timeout: 10) else {
            throw PlayFailure("The painting has no play state readout")
        }
        _ = try await settle(app)
        return app
    }

    @MainActor
    private func runMailbox(_ mailbox: URL, app: XCUIApplication, moveLimit: Int? = nil,
                            idleTimeout: TimeInterval? = nil) async throws {
        let initial = try await settle(app)
        try PlayWire.publish(["version": 1, "state": initial.object], named: "hello.json", in: mailbox)
        var number = 1
        while moveLimit.map({ number <= $0 }) ?? true {
            let path = mailbox.appending(path: "move-\(number).json")
            let deadline = idleTimeout.map { Date().addingTimeInterval($0) }
            while !FileManager.default.fileExists(atPath: path.path) {
                try Task.checkCancellation()
                if let deadline, Date() >= deadline { throw PlayFailure("Timed out waiting for move \(number)") }
                try await Task.sleep(for: .milliseconds(50))
            }
            let acknowledgement: [String: Any]
            let filename: String
            do {
                let move = try PlayMove(data: Data(contentsOf: path))
                try await perform(move, app: app)
                let state = try await settle(app)
                if case let .fill(area) = move, !state.filledAreas.contains(area) {
                    throw PlayFailure("Tapping area \(area) did not fill it")
                }
                acknowledgement = ["state": state.object]
                filename = "done-\(number).json"
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                acknowledgement = ["reason": String(describing: error)]
                filename = "error-\(number).json"
            }
            // A publication failure is a runner failure, never a second acknowledgement.
            try PlayWire.publish(acknowledgement, named: filename, in: mailbox)
            number += 1
        }
    }

    @MainActor
    private func perform(_ move: PlayMove, app: XCUIApplication) async throws {
        switch move {
        case let .fill(number):
            let before = try readState(app)
            guard number <= before.areaCount else { throw PlayFailure("Area \(number) does not exist") }
            if before.filledAreas.contains(number) { return }
            let area = app.buttons["area-\(number)"]
            guard area.exists, let paintText = area.value as? String, let paint = Int(paintText), paint > 0 else {
                throw PlayFailure("Area \(number) has no label point")
            }
            guard app.descendants(matching: .any)["canvas"].frame.contains(area.frame) else {
                throw PlayFailure("Area \(number) is outside the canvas view")
            }
            if before.selectedPaint != paint {
                let swatch = app.buttons["swatch-\(paint)"]
                guard swatch.exists, swatch.isHittable else { throw PlayFailure("Paint \(paint) is not tappable") }
                swatch.tap()
                _ = try await settle(app)
                guard try readState(app).selectedPaint == paint else { throw PlayFailure("Paint \(paint) was not selected") }
            }
            // A coordinate tap avoids hittability ambiguity for neighbouring small areas.
            area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        case let .tap(label):
            let matches = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
                .allElementsBoundByIndex.filter { $0.isHittable }
            guard matches.count == 1, let target = matches.first else {
                throw PlayFailure("Expected one tappable element labelled \(label); found \(matches.count)")
            }
            target.tap()
        case let .drag(from, to, steps):
            // UIImage.size may already be pixels in the test runner. Read the simulator's
            // actual canvas display scale instead of assuming the screenshot's UIImage scale.
            let image = XCUIScreen.main.screenshot().image
            guard let pixels = image.cgImage else { throw PlayFailure("Cannot read screenshot dimensions") }
            guard let scaleText = app.descendants(matching: .any)["play-screen-scale"].value as? String,
                  let scale = Double(scaleText), scale.isFinite, scale > 0 else {
                throw PlayFailure("Cannot read simulator screen scale")
            }
            let window = app.windows.firstMatch
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: CGFloat(x / scale), y: CGFloat(y / scale))
            }
            let start = point(from.x, from.y), end = point(to.x, to.y)
            guard from.x < Double(pixels.width), to.x < Double(pixels.width),
                  from.y < Double(pixels.height), to.y < Double(pixels.height),
                  window.frame.contains(start), window.frame.contains(end) else {
                throw PlayFailure("Drag endpoints are outside the app window")
            }
            let origin = window.coordinate(withNormalizedOffset: .zero)
            func coordinate(_ fraction: CGFloat) -> XCUICoordinate {
                origin.withOffset(CGVector(
                    dx: start.x + (end.x - start.x) * fraction - window.frame.minX,
                    dy: start.y + (end.y - start.y) * fraction - window.frame.minY))
            }
            // Public XCUITest exposes endpoint drags. Execute each interpolated segment once.
            for step in 0..<steps {
                try Task.checkCancellation()
                coordinate(CGFloat(step) / CGFloat(steps)).press(
                    forDuration: 0.35, thenDragTo: coordinate(CGFloat(step + 1) / CGFloat(steps)))
            }
        case let .wait(seconds):
            // Chunk large waits so cancellation remains prompt, without imposing a wire limit.
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                try await Task.sleep(for: .seconds(min(0.25, deadline.timeIntervalSinceNow)))
            }
        case .screenshot: break
        }
    }

    @MainActor
    private func readState(_ app: XCUIApplication) throws -> PlayState {
        guard let json = app.descendants(matching: .any)["play-state"].value as? String else {
            throw PlayFailure("The current screen has no play state readout")
        }
        return try PlayState(data: Data(json.utf8))
    }

    @MainActor
    private func settle(_ app: XCUIApplication) async throws -> PlayState {
        let deadline = Date().addingTimeInterval(20)
        var last: PlayState?
        var stableSince = Date()
        while Date() < deadline {
            try Task.checkCancellation()
            let state = try readState(app)
            let settled = app.descendants(matching: .any)["play-settled"].value as? String == "1"
            if !settled || state != last { stableSince = Date() }
            last = state
            // Also allow SwiftUI's chrome to finish after the canvas becomes idle.
            if settled, Date().timeIntervalSince(stableSince) >= 0.5 { return state }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw PlayFailure("Painting did not settle within 20 seconds")
    }

    @MainActor
    private func requireFreshMailbox(_ mailbox: URL) throws {
        guard mailbox.path.hasPrefix("/"),
              try FileManager.default.contentsOfDirectory(atPath: mailbox.path).isEmpty else {
            throw PlayFailure("PLAY_MAILBOX must name a fresh empty directory")
        }
    }

    @MainActor
    private func state(in envelope: [String: Any]) throws -> PlayState {
        guard let state = envelope["state"] as? [String: Any] else { throw PlayFailure("Missing state envelope") }
        return try PlayState(data: JSONSerialization.data(withJSONObject: state))
    }

    @MainActor
    private func response(_ name: String, in mailbox: URL, errorNumber: Int? = nil) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(40)
        let path = mailbox.appending(path: name)
        while Date() < deadline {
            if let errorNumber {
                let error = mailbox.appending(path: "error-\(errorNumber).json")
                if FileManager.default.fileExists(atPath: error.path) {
                    throw PlayFailure(String(decoding: try Data(contentsOf: error), as: UTF8.self))
                }
            }
            if FileManager.default.fileExists(atPath: path.path) {
                guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any] else {
                    throw PlayFailure("Invalid response: \(name)")
                }
                return object
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw PlayFailure("Timed out waiting for \(name)")
    }
}
#endif
