import Foundation
@testable import PaintCore

/// Colors the two color-naming suites share (`ColorNamingTests`, `ColorNicknameTests`).
enum ColorFixtures {

    /// A color given as RRGGBB hex digits → OKLab, the way the vocabulary reads its anchors.
    static func lab(_ hex: String) -> SIMD3<Float> {
        ColorScience.okLab(hex: UInt32(hex, radix: 16)!)
    }

    /// One line of `samplePalettes`: a sample's palette color and the name it should get.
    struct Swatch: Sendable {
        let sample: String
        let hex: String
        let name: String
    }

    /// The six corpus photos' 24-color palettes (`Tests/Corpus`), "<sample> <hex> <expected
    /// name>" per line, from `pbn` at `--colors 24`; the names were reviewed by eye against the
    /// swatches.
    private static let samplePalettes = """
        barn f77b5c light vivid red
        barn c66148 vivid red
        barn 8e4f3f red
        barn f9b38b light orange
        barn 6d3e33 dark red
        barn 563128 dark red
        barn bca48b beige
        barn a88c76 orange
        barn 927763 light brown
        barn 736751 grayish brown
        barn 5f513d brown
        barn 453e2b dark olive
        barn 312419 dark brown
        barn fee3ad light beige
        barn cfb96d yellow
        barn b29f5f light olive
        barn 958856 olive
        barn 747846 olive
        barn 61693c olive
        barn 4e552f olive
        barn f9efe6 white
        barn c2b4b4 light gray
        barn 9d9aa1 gray
        barn 79797b gray
        espresso e4bb94 beige
        espresso d8a274 orange
        espresso e89339 vivid orange
        espresso c98857 orange
        espresso c97239 vivid orange
        espresso b26b3f dark orange
        espresso ba5a25 dark orange
        espresso 8c6040 brown
        espresso b73414 vivid red
        espresso a14e25 dark orange
        espresso a1260d vivid red
        espresso 8d3919 brown
        espresso 70442c brown
        espresso 731607 dark red
        espresso 572a18 brown
        espresso 4b0d05 very dark red
        espresso 2c0e06 very dark red
        espresso 1b0502 black
        espresso f1d8bc light beige
        espresso c8ae8e beige
        espresso bc9672 orange
        espresso a07a57 light brown
        espresso f7eee3 white
        hibiscus d9a78b beige
        hibiscus b7836d orange
        hibiscus b3605a red
        hibiscus c83c27 vivid red
        hibiscus 9e3a28 vivid red
        hibiscus 7f351d brown
        hibiscus 986b55 brown
        hibiscus e9cea6 beige
        hibiscus 68563f brown
        hibiscus 523e27 brown
        hibiscus a1a650 light olive
        hibiscus 888e47 olive
        hibiscus 747832 olive
        hibiscus 606424 olive
        hibiscus 51511c olive
        hibiscus afaa89 beige
        hibiscus 9b967b light grayish olive
        hibiscus 8a846e grayish olive
        hibiscus 717361 grayish olive
        hibiscus 413f14 dark olive
        hibiscus 352e12 dark olive
        hibiscus 566258 grayish green
        hibiscus 434b44 dark gray
        hibiscus 262218 very dark gray
        lighthouse 834638 red
        lighthouse 865d42 brown
        lighthouse fcfacd light beige
        lighthouse e1d7ae beige
        lighthouse c5bc9b beige
        lighthouse b9a57d beige
        lighthouse a49473 light brown
        lighthouse 908164 light brown
        lighthouse 7e6f4f brown
        lighthouse 6b5e42 brown
        lighthouse 604f3c brown
        lighthouse 525028 olive
        lighthouse 4d4031 brown
        lighthouse 3e3b1f dark olive
        lighthouse 6b8799 grayish blue
        lighthouse a4a695 light grayish olive
        lighthouse 869695 gray
        lighthouse 73766c gray
        lighthouse 596162 gray
        lighthouse 494f4e dark gray
        lighthouse 394042 dark gray
        lighthouse 3c3229 grayish brown
        lighthouse 2e261f very dark gray
        lighthouse 221915 black
        parrots d19195 pink
        parrots e34c40 vivid red
        parrots a75d55 red
        parrots bc3b33 vivid red
        parrots 91362e vivid red
        parrots 6b3129 dark red
        parrots e2c6c9 grayish pink
        parrots eebd0e vivid yellow
        parrots b59b22 light olive
        parrots ceccb1 beige
        parrots a0ab7e green
        parrots 706953 grayish olive
        parrots 575848 grayish olive
        parrots 779354 olive
        parrots 5c8430 olive
        parrots 5d713c olive
        parrots 45582a olive
        parrots 689c9e teal
        parrots 4c7b82 teal
        parrots f3eae7 white
        parrots b6afaf light gray
        parrots 928f86 gray
        parrots 403e33 dark gray
        parrots 2e2a26 very dark gray
        regatta b8768c dark pink
        regatta 80536d purple
        regatta ab4d3e red
        regatta 853d35 red
        regatta 62262e dark red
        regatta d9a1a9 pink
        regatta 5b4639 brown
        regatta 775a20 brown
        regatta d9cf7f yellow
        regatta c0af46 dark yellow
        regatta a99b44 light olive
        regatta 897d3a olive
        regatta e6e9ce grayish yellow
        regatta cccfb8 grayish yellow
        regatta 243255 navy
        regatta b5b8a7 grayish green
        regatta 949c92 gray
        regatta 7f8782 gray
        regatta 6c7573 gray
        regatta 5a6262 gray
        regatta 424d56 dark grayish blue
        regatta 39393a dark gray
        regatta 251d21 black
        """

    /// `samplePalettes` parsed, in order.
    static let swatches: [Swatch] = samplePalettes.split(separator: "\n").map { line in
        var words = line.split(separator: " ").map(String.init)
        let sample = words.removeFirst(), hex = words.removeFirst()
        return Swatch(sample: sample, hex: hex, name: words.joined(separator: " "))
    }

    /// The corpus photos whose palettes `samplePalettes` holds.
    static let samples = Array(Set(swatches.map(\.sample))).sorted()

    /// A corpus photo's palette, by name.
    static func palette(of sample: String) -> [PaletteColor] {
        swatches.filter { $0.sample == sample }.map { PaletteColor(oklab: lab($0.hex), space: .sRGB) }
    }
}
