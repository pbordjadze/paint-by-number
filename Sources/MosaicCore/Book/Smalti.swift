/// Smalti a mosaicist can order, for the stone list's codes (painting-company row 367).
///
/// `orsoni` is the range of Orsoni of Venice smalti that Mosaic Workshop (London) sells, by its codes
/// S01 to S98 (there is no S47), from mosaicworkshop.com/orsoni-smalti as fetched on November 20,
/// 2026. Orsoni itself publishes no list of codes. Each colour is read from the shop's photo of the
/// smalti: the median of the pile's pixels (those that differ from the white background by more
/// than 25), between its 30th and 85th lightness percentile, so the glints and the shadows are left
/// out. A photo's colour is only near the glass's, so the stone list says to check against samples.
public enum Smalti {
    public struct Entry: Sendable, Equatable {
        /// The shop's code, as it is ordered: "S23".
        public let code: String
        /// sRGB, 0xRRGGBB, as read from the photo.
        public let hex: UInt32

        public var rgb: SIMD3<Double> {
            SIMD3(Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF)) / 255
        }
    }

    public static let orsoni: [Entry] = [
        Entry(code: "S01", hex: 0x2D2B5D),
        Entry(code: "S02", hex: 0x292B77),
        Entry(code: "S03", hex: 0x2C38A9),
        Entry(code: "S04", hex: 0x3B4AB6),
        Entry(code: "S05", hex: 0x4B5DC1),
        Entry(code: "S06", hex: 0x7A8DDC),
        Entry(code: "S07", hex: 0x95A5DD),
        Entry(code: "S08", hex: 0xC4CEE6),
        Entry(code: "S09", hex: 0xCDD3E1),
        Entry(code: "S10", hex: 0xD1D4DA),
        Entry(code: "S11", hex: 0xC3C7C5),
        Entry(code: "S12", hex: 0xDCD8D0),
        Entry(code: "S13", hex: 0x33557C),
        Entry(code: "S14", hex: 0x3165AB),
        Entry(code: "S15", hex: 0x3967A6),
        Entry(code: "S16", hex: 0x6188C3),
        Entry(code: "S17", hex: 0x6B94D2),
        Entry(code: "S18", hex: 0x749BCE),
        Entry(code: "S19", hex: 0xB5CBDB),
        Entry(code: "S20", hex: 0xD2DDE3),
        Entry(code: "S21", hex: 0xCBD1D9),
        Entry(code: "S22", hex: 0xB0B879),
        Entry(code: "S23", hex: 0x8A9A58),
        Entry(code: "S24", hex: 0x6D9365),
        Entry(code: "S25", hex: 0x568260),
        Entry(code: "S26", hex: 0x457756),
        Entry(code: "S27", hex: 0x284F3A),
        Entry(code: "S28", hex: 0x1B6C4C),
        Entry(code: "S29", hex: 0x74392C),
        Entry(code: "S30", hex: 0x593933),
        Entry(code: "S31", hex: 0x583931),
        Entry(code: "S32", hex: 0x5F3D31),
        Entry(code: "S33", hex: 0x3D3C3D),
        Entry(code: "S34", hex: 0x4F4A4C),
        Entry(code: "S35", hex: 0x313131),
        Entry(code: "S36", hex: 0x4A4945),
        Entry(code: "S37", hex: 0x6E6E69),
        Entry(code: "S38", hex: 0x62625E),
        Entry(code: "S39", hex: 0x82817C),
        Entry(code: "S40", hex: 0x676867),
        Entry(code: "S41", hex: 0xA2A5A2),
        Entry(code: "S42", hex: 0xC4C4C0),
        Entry(code: "S43", hex: 0xBEB9AE),
        Entry(code: "S44", hex: 0x474141),
        Entry(code: "S45", hex: 0x453328),
        Entry(code: "S46", hex: 0x694B3D),
        Entry(code: "S48", hex: 0x73492D),
        Entry(code: "S49", hex: 0x8B5B38),
        Entry(code: "S50", hex: 0xC28232),
        Entry(code: "S51", hex: 0xD5A23A),
        Entry(code: "S52", hex: 0xF3DC71),
        Entry(code: "S53", hex: 0xE7CDB5),
        Entry(code: "S54", hex: 0xEBCDAE),
        Entry(code: "S55", hex: 0xCFA682),
        Entry(code: "S56", hex: 0xB58866),
        Entry(code: "S57", hex: 0xB68669),
        Entry(code: "S58", hex: 0x95613E),
        Entry(code: "S59", hex: 0x905533),
        Entry(code: "S60", hex: 0x67483C),
        Entry(code: "S61", hex: 0xD8D8D1),
        Entry(code: "S62", hex: 0x9D9294),
        Entry(code: "S63", hex: 0x8C7F82),
        Entry(code: "S64", hex: 0x756166),
        Entry(code: "S65", hex: 0x776366),
        Entry(code: "S66", hex: 0x4D3B3E),
        Entry(code: "S67", hex: 0x6E5659),
        Entry(code: "S68", hex: 0x2C3193),
        Entry(code: "S69", hex: 0x395CA4),
        Entry(code: "S70", hex: 0x4875A8),
        Entry(code: "S71", hex: 0x418B86),
        Entry(code: "S72", hex: 0x62AB84),
        Entry(code: "S73", hex: 0x5D9953),
        Entry(code: "S74", hex: 0xAFC029),
        Entry(code: "S75", hex: 0x593734),
        Entry(code: "S76", hex: 0x5E2C2B),
        Entry(code: "S77", hex: 0x7F2028),
        Entry(code: "S78", hex: 0x7F2429),
        Entry(code: "S79", hex: 0xB42423),
        Entry(code: "S80", hex: 0xF97F35),
        Entry(code: "S81", hex: 0xFDB329),
        Entry(code: "S82", hex: 0xDCAA04),
        Entry(code: "S83", hex: 0xE4CA02),
        Entry(code: "S84", hex: 0xABA156),
        Entry(code: "S85", hex: 0x657043),
        Entry(code: "S86", hex: 0x4F6941),
        Entry(code: "S87", hex: 0x41BED2),
        Entry(code: "S88", hex: 0x0688B4),
        Entry(code: "S89", hex: 0x1F82A7),
        Entry(code: "S90", hex: 0x0A487B),
        Entry(code: "S91", hex: 0x5D9798),
        Entry(code: "S92", hex: 0xB0CECD),
        Entry(code: "S93", hex: 0xB3C4BE),
        Entry(code: "S94", hex: 0xC9C2AF),
        Entry(code: "S95", hex: 0xA69E94),
        Entry(code: "S96", hex: 0x9A8E79),
        Entry(code: "S97", hex: 0xCF91BA),
        Entry(code: "S98", hex: 0xCCA2C3),
    ]

    private static let labs = orsoni.map { StoneBook.oklab($0.rgb) }

    /// The nearest smalto to an sRGB colour (0...1) that isn't `taken`, and its distance (ΔE,
    /// OKLab); ties to the earlier code. Nil when every one is taken.
    public static func nearest(to rgb: SIMD3<Double>, excluding taken: Set<String> = []) -> (entry: Entry, distance: Double)? {
        let lab = StoneBook.oklab(rgb)
        var best = -1, bestD = Double.infinity
        for (i, l) in labs.enumerated() where !taken.contains(orsoni[i].code) {
            let d = StoneBook.distance(lab, l)
            if d < bestD { bestD = d; best = i }
        }
        return best < 0 ? nil : (orsoni[best], bestD)
    }
}
