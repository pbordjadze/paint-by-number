import Foundation

/// The timing of a pet's moves, from the spec's numbers. `h` is the pet's height in pixels.
extension ShowSpec.Crew {
    /// Seconds from setting off to arriving `dist` px away.
    func walkTime(_ dist: Double, _ h: Double) -> Double {
        lean + dist / (walk * h) + 0.5 * (accel + decel)
    }

    /// Seconds to draw a line `dist` px long, walking along it.
    func traceTime(_ dist: Double, _ h: Double) -> Double {
        dist / (trace * h) + 0.5 * (traceRamp.up + traceRamp.down)
    }

    /// Distance walked `tau` s after the lean.
    func travelled(_ tau: Double, _ dist: Double, _ h: Double) -> Double {
        trapezoid(tau, dist, walk * h, accel, decel)
    }

    /// Distance drawn `tau` s into tracing a line.
    func traced(_ tau: Double, _ dist: Double, _ h: Double) -> Double {
        trapezoid(tau, dist, trace * h, traceRamp.up, traceRamp.down)
    }
}

/// Distance covered `tau` s into a move of `dist` at top speed `v`, speeding up over `acc` s and
/// slowing over `dec` s.
func trapezoid(_ tau: Double, _ dist: Double, _ v: Double, _ acc: Double, _ dec: Double) -> Double {
    if dist <= 0 { return 0 }
    var acc = acc
    var dec = dec
    var v = v
    var cruise = dist / v - 0.5 * (acc + dec)
    if cruise < 0 {                     // too short to reach full speed: scale the ramps
        let k = (dist / v / (0.5 * (acc + dec))).squareRoot()
        acc *= k
        dec *= k
        v *= k
        cruise = 0
    }
    let total = acc + cruise + dec
    let tau = min(max(tau, 0), total)
    if tau < acc { return 0.5 * v * tau * tau / acc }
    var d = 0.5 * v * acc
    if tau < acc + cruise { return d + v * (tau - acc) }
    d += v * cruise
    let r = tau - acc - cruise
    return min(dist, d + v * r - 0.5 * v * r * r / dec)
}

/// A damped spring's offset `t` s after a kick of `amount`.
func spring(_ t: Double, _ amount: Double, period: Double = 0.2, decay: Double = 0.07) -> Double {
    if t < 0 { return 0 }
    return amount * exp(-t / decay) * cos(2 * .pi * t / period)
}
