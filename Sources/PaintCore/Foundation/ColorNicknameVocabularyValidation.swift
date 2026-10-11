import Foundation

extension ColorNickname {
    /// A frozen built-in vocabulary, or a proposed table for the color-name taste loop.
    /// Table order breaks distance ties and participates in the seeded draw; never reorder v1.
    public struct Vocabulary: Sendable {
        /// Original table text. Version 1 is hashed as UTF-8, with no trailing newline.
        public let table: String
        public let entries: [Entry]
        /// Malformed rows, also included in `problems()`. Renderers must reject these rows.
        public let formatProblems: [String]

        private static let version1 = Vocabulary(table: ColorNickname.table)

        /// Unknown future versions resolve to the newest vocabulary this build knows.
        /// Missing artwork metadata must explicitly select 1, never `currentVersion`.
        public init(version: Int) {
            // Only v1 ships today. Add future versions without editing v1 or its draw.
            self = Self.version1
        }

        /// RRGGBB<TAB>Name, one entry per line, no header. The frozen table's single-space
        /// separator is accepted too. A final newline and CRLF line endings are allowed.
        /// Malformed rows are reported by `problems()` and never become black anchors.
        public init(table: String) {
            self.table = table
            var entries: [Entry] = []
            var problems: [String] = []
            var lines = table.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            if lines.last == "" { lines.removeLast() }
            for (index, raw) in lines.enumerated() {
                let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
                let digits = line.prefix(6)
                let separator = line.dropFirst(6).first
                guard digits.count == 6,
                      digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }),
                      separator == "\t" || separator == " ", line.count > 7,
                      !line.dropFirst(7).contains("\t"),
                      let hex = UInt32(digits, radix: 16) else {
                    problems.append("line \(index + 1): expected RRGGBB<TAB>Name (uppercase hex)")
                    continue
                }
                entries.append(Entry(name: String(line.dropFirst(7)), hex: hex, oklab: ColorScience.okLab(hex: hex)))
            }
            self.entries = entries
            formatProblems = problems
        }

        /// Mechanical style-guide and gamut checks. Diagnostics have a stable order so the
        /// CLI and the tests judge proposed tables with the same oracle.
        public func problems() -> [String] {
            var problems = formatProblems
            if !(480...640).contains(entries.count) {
                problems.append("\(entries.count) entries: expected 480...640")
            }
            var names = Set<String>()
            var anchors = Set<UInt32>()
            var leading: [String: Int] = [:]
            var trailing: [String: Int] = [:]
            for entry in entries {
                let name = entry.name
                if !names.insert(name).inserted { problems.append("\(name): duplicate name") }
                if !anchors.insert(entry.hex).inserted {
                    problems.append(String(format: "#%06X: duplicate anchor", entry.hex))
                }
                let words = name.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
                if !(1...2).contains(words.count) { problems.append("\(name): one or two words") }
                if name.count > 16 { problems.append("\(name): at most 16 characters") }
                if !name.unicodeScalars.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || $0 == " " || $0 == "-") }) {
                    problems.append("\(name): ASCII letters, spaces and a hyphen only")
                }
                if name.filter({ $0 == "-" }).count > 1 { problems.append("\(name): at most one hyphen") }
                for word in words {
                    if word.first?.isUppercase != true || !word.dropFirst().allSatisfy({ $0.isLowercase || $0 == "-" }) {
                        problems.append("\(name): Title Case")
                    }
                }
                if words.count == 1 {
                    if Self.colorWords.contains(name.lowercased()) { problems.append("\(name): a plain color word alone") }
                } else if words.count == 2 {
                    leading[words[0], default: 0] += 1
                    trailing[words[1], default: 0] += 1
                }
                let family = ColorName(oklab: entry.oklab).family
                for word in name.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }) {
                    if Self.forbidden.contains(String(word)) { problems.append("\(name) uses “\(word)”") }
                    if let allowed = Self.families[String(word)], !allowed.contains(family) {
                        problems.append("\(name) is a \(family) anchor (#\(String(entry.hex, radix: 16)))")
                    }
                }
            }
            for word in leading.keys.sorted() where leading[word]! > 4 {
                problems.append("\(leading[word]!) names start with \(word): at most 4")
            }
            for word in trailing.keys.sorted() where trailing[word]! > 6 {
                problems.append("\(trailing[word]!) names end with \(word): at most 6")
            }
            // The same 24³ grid as the original gamut lint: every in-gamut point needs five
            // anchors within ΔE 0.10. Bound diagnostics while still checking every sample.
            let steps = 24
            func value(_ i: Int, _ low: Float, _ high: Float) -> Float {
                low + (high - low) * Float(i) / Float(steps - 1)
            }
            var gaps = 0
            for l in 0..<steps {
                for a in 0..<steps {
                    for b in 0..<steps {
                        let point = SIMD3(value(l, 0, 1), value(a, -0.24, 0.285), value(b, -0.32, 0.21))
                        let rgb = ColorScience.okLabToLinearSRGB(point)
                        guard rgb.min() >= -1e-7 && rgb.max() <= 1 + 1e-6 else { continue }
                        let near = entries.reduce(0) { $0 + (ColorScience.distance($1.oklab, point) <= 0.10 ? 1 : 0) }
                        if near < 5 {
                            if gaps < 8 { problems.append("gamut: \(point) has \(near) anchors within ΔE 0.10 (needs 5)") }
                            gaps += 1
                        }
                    }
                }
            }
            if gaps > 8 { problems.append("gamut: \(gaps) sample points have fewer than five nearby anchors") }
            return problems
        }

        private static let colorWords: Set<String> = [
            "red", "orange", "yellow", "green", "blue", "purple", "pink", "brown", "gray", "grey",
            "black", "white", "beige", "olive", "teal", "navy", "magenta", "violet", "indigo",
            "lime", "aqua", "turquoise", "tan", "cyan", "maroon", "mauve", "crimson", "scarlet",
            "lavender", "lilac", "coral", "peach", "cream", "ivory", "gold", "silver", "bronze",
            "khaki", "fuchsia", "amber", "rose", "plum", "mint", "sage", "rust", "sand",
        ]

        private static let forbidden: Set<String> = [
            // skin tones and body parts
            "skin", "flesh", "nude", "tan", "blush", "ivory", "ebony", "porcelain", "fair", "bone", "cheek", "lip", "lips",
            "hair", "blood", "heart", "eye", "eyes", "tooth", "teeth", "nail", "finger", "hand", "tongue", "vein", "bruise",
            "breast", "comb", "foot", "face", "head", "belly", "bile", "scab", "rash", "vomit", "mucus",
            // brands and people
            "cola", "coke", "pepsi", "tiffany", "crayola", "sharpie", "lego", "kleenex", "popsicle", "creamsicle", "tabasco",
            "nutella", "oreo", "starbucks", "pantone", "persian", "indian", "prussian", "sienna", "titian",
            // religion, politics, medicine
            "angel", "heaven", "saint", "monk", "pope", "cathedral", "church", "temple", "altar", "holy", "sacred", "easter",
            "christmas", "cardinal", "royal", "liberty", "republic", "rebel", "revolution", "pill", "aspirin", "bandage",
            "surgical", "hospital", "iodine", "calamine", "antiseptic", "tobacco", "nicotine",
            // superlatives
            "best", "perfect", "ultimate", "supreme", "greatest", "brightest", "darkest", "finest", "purest", "ultra",
            "super", "mega", "most", "utmost",
        ]

        private static let families: [String: Set<ColorName.Family>] = [
            "red": [.red], "orange": [.orange], "yellow": [.yellow], "green": [.green, .olive], "blue": [.blue, .navy],
            "purple": [.purple], "pink": [.pink], "brown": [.brown], "gray": [.gray], "grey": [.gray],
            "black": [.black], "white": [.white], "beige": [.beige], "olive": [.olive, .green], "teal": [.teal],
            "navy": [.navy], "magenta": [.magenta, .purple, .pink],
        ]
    }
}
