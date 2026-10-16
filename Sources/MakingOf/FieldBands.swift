import PaintCore

/// How the field show cuts its parallel work into bands: `Parallel.forEachBand`, whose bands follow
/// the core count (two for each), except that a test can fix their number (`count`) to cut the work
/// as a machine with other cores would. No band of the field show reads another's output or adds
/// to a sum, so what it makes must not depend on the cut (`FieldShowTests`).
enum FieldBands {
    /// The number of bands to cut into, if fixed.
    @TaskLocal static var count: Int?

    /// Runs `body` over disjoint sub-ranges covering `0..<count`, in parallel.
    static func forEach(_ count: Int, _ body: (Range<Int>) -> Void) {
        guard let bands = Self.count, count > 0 else { return Parallel.forEachBand(count, body) }
        Parallel.forEachChunk(count, chunk: (count + bands - 1) / bands, body)
    }
}
