import Foundation
import SwiftUI

/// When the painting screen shows the source photo over the canvas. Holding the Photo
/// control peeks for as long as it is held; a quick tap keeps the photo shown (like the `p`
/// key and VoiceOver's activate) until the next tap on the control or on the canvas.
struct PhotoPeek {
    /// Presses shorter than this are taps.
    static let tapDuration: TimeInterval = 0.3

    private(set) var isLatched: Bool
    private(set) var isPressed = false
    private var pressStart: TimeInterval = 0
    private var latchedAtPress = false

    init(latched: Bool = false) {
        isLatched = latched
    }

    var isShown: Bool { isLatched || isPressed }

    mutating func pressBegan(at time: TimeInterval) {
        guard !isPressed else { return }
        isPressed = true
        pressStart = time
        latchedAtPress = isLatched
    }

    /// A press on a latched photo hides it however long it was; otherwise a tap latches and
    /// a hold leaves the latch as it is.
    mutating func pressEnded(at time: TimeInterval) {
        guard isPressed else { return }
        isPressed = false
        if latchedAtPress {
            isLatched = false
        } else if time - pressStart < Self.tapDuration {
            isLatched = true
        }
    }

    /// The menu or keyboard toggle, VoiceOver, or a canvas touch.
    mutating func setLatched(_ latched: Bool) {
        isLatched = latched
    }
}

/// The top bar's Photo control: touch and hold to compare the painting with its photo, tap
/// to keep the photo shown. Tinted glass while the photo shows.
struct PhotoPeekButton: View {
    @Binding var peek: PhotoPeek
    @GestureState private var isPressing = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: peek.isShown ? "photo.fill" : "photo")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(peek.isShown ? Color.white : Color.primary)
            .opacity(isEnabled ? 1 : 0.35)
            .frame(width: 44, height: 44)
            // Not interactive glass: it would take the touches this control handles itself.
            .glassEffect(peek.isShown ? Glass.regular.tint(Theme.accent) : Glass.regular, in: .circle)
            .scaleEffect(isPressing && isEnabled ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressing)
            .contentShape(.circle)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, pressing, _ in pressing = true }
                    .onChanged { _ in press(down: true) }
                    .onEnded { _ in press(down: false) })
            // Gesture state resets when the system cancels the touch, which never calls onEnded.
            .onChange(of: isPressing) { _, pressing in
                if !pressing { press(down: false) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Photo"))
            .accessibilityValue(Text(peek.isShown ? "Showing" : "Hidden"))
            .accessibilityHint(Text("Touch and hold to compare with the photo. Tap to keep it shown."))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { peek.setLatched(!peek.isLatched) }
    }

    /// `.disabled` doesn't stop a custom gesture, so a press is ignored here; a release
    /// always goes through so the photo can't stay stuck on.
    private func press(down: Bool) {
        let time = ProcessInfo.processInfo.systemUptime
        if down {
            guard isEnabled else { return }
            peek.pressBegan(at: time)
        } else {
            peek.pressEnded(at: time)
        }
    }
}
