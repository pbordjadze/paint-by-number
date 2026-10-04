import Foundation
import Observation
import PaintCore
import SwiftUI
import UIKit

/// Transient chrome reactions to painting events, undo registration, and the tips they feed.
@Observable
final class PaintChromeState {
    /// Per color: bumped to shake its swatch.
    var shakes: [Int: Int] = [:]
    /// The window's undo manager: every fill is registered with it (⌘Z, the Edit menu,
    /// three-finger undo and redo).
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var observed: ObjectIdentifier?

    func observe(_ session: PaintingSession, controller: CanvasController) {
        guard observed != ObjectIdentifier(session) else { return }
        observed = ObjectIdentifier(session)
        PaintTips.paintingOpened(hasProgress: session.progress.paintedCount > 0)
        session.onEvent { [weak self, weak controller, weak session] event in
            if let session, let signal = PaintTips.signal(for: event, isStroking: session.isStroking) {
                PaintTips.record(signal)
            }
            switch event {
            case let .painted(regions, _):
                if let session, !session.isStroking { self?.registerUndo(of: regions.count, in: session) }
            case let .strokeEnded(regions):
                if let session { self?.registerUndo(of: regions.count, in: session) }
            case let .rejected(_, expected):
                // Without animation the shake's whole-number step leaves the swatch in place.
                withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .linear(duration: 0.45)) {
                    self?.shakes[expected, default: 0] += 1
                }
            case let .colorCompleted(color):
                if let session {
                    Announcer.announce(PaintSpeech.colorFinished(number: color + 1, name: session.colorNames[color], nickname: session.nickname(of: color)))
                }
            case .artworkCompleted:
                Announcer.announce(PaintSpeech.paintingFinished)
                controller?.zoomToFit()
            default:
                break
            }
        }
    }

    /// Undo takes back the fills of one tap or one whole stroke. Redoing paints them again,
    /// which registers the next undo through the same event.
    private func registerUndo(of count: Int, in session: PaintingSession) {
        guard let undoManager else { return }
        // UndoManager calls back on the thread that undoes: the main thread.
        undoManager.registerUndo(withTarget: session) { [weak self] session in
            MainActor.assumeIsolated { self?.undoFills(count, in: session) }
        }
        undoManager.setActionName(String(localized: "Paint"))
    }

    private func undoFills(_ count: Int, in session: PaintingSession) {
        let undone = (0..<count).compactMap { _ in session.undo() }
        guard let undoManager, let first = undone.first else { return }
        undoManager.registerUndo(withTarget: session) { session in
            MainActor.assumeIsolated {
                let origin = session.template.labels(ofRegion: first).first?.position ?? .zero
                session.paint(undone.reversed(), from: origin, animated: true)
            }
        }
        undoManager.setActionName(String(localized: "Paint"))
    }
}
