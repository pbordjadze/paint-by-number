/// Smoothstep: 0 below 0, 1 above 1, 3x^2 - 2x^3 between (`ease` in `making_of_pets.py`).
func ease(_ x: Double) -> Double {
    let x = min(max(x, 0), 1)
    return x * x * (3 - 2 * x)
}
