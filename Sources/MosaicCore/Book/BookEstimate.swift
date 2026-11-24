#if canImport(FoundationEssentials) && !canImport(Darwin)
import FoundationEssentials
#else
import Foundation
#endif

/// The cover's two estimates, as ranges and round numbers: they are a guide, not a quote.
extension StoneBook {
    /// Pieces an hour, cut at the nippers and glued to the mesh: a beginner's, and a practised
    /// hand's. Setting a mesh sheet into the bed and grouting it are counted per sheet.
    static let piecesPerHour = (slow: 45.0, quick: 90.0)
    static let hoursPerSheet = (slow: 1.0, quick: 0.5)

    /// The hours from the first cut to the last wipe of grout, low and high, rounded to 5.
    public var hoursToSet: ClosedRange<Int> {
        let n = Double(pieces.count), sheets = Double(sections.count)
        func round5(_ h: Double) -> Int { max(5, Int((h / 5).rounded()) * 5) }
        let low = round5(n / StoneBook.piecesPerHour.quick + sheets * StoneBook.hoursPerSheet.quick)
        let high = round5(n / StoneBook.piecesPerHour.slow + sheets * StoneBook.hoursPerSheet.slow)
        return low...max(low, high)
    }

    /// What the stones cost, in pounds, as Mosaic Workshop sells them: 100 g bags of a code
    /// (`Smalti.Entry.bagPounds`), whole bags of each. Gold leaf smalti is priced at
    /// `goldPoundsPer100g`; the tools, mesh, bed and grout aren't counted.
    public var stonePounds: Double {
        stones.reduce(0) { sum, s in
            let bags = (s.kilograms * 10).rounded(.up)
            let price = s.kind == .gold ? StoneBook.goldPoundsPer100g : (s.smalto?.bagPounds ?? Smalti.Entry.commonBagPounds)
            return sum + bags * price
        }
    }

    /// Gold leaf smalti, 100 g: Mosaic Workshop lists no price by weight; Mosaic Shop (Belgium)
    /// sells 25 g for €15.32 (November 20, 2026), about £13.
    static let goldPoundsPer100g = 52.0
}

extension Smalti.Entry {
    /// The colours most bags cost: £6 for 100 g, about 35 smalti.
    static let commonBagPounds = 6.0

    /// A 100 g bag's price at Mosaic Workshop, by code, as listed on November 20, 2026: £8 for
    /// S28–S32, S50–S60 and S75–S83, £7 for S84–S98, £6 for the rest.
    public var bagPounds: Double {
        let n = Int(code.dropFirst()) ?? 0
        switch n {
        case 28...32, 50...60, 75...83: return 8
        case 84...98: return 7
        default: return Smalti.Entry.commonBagPounds
        }
    }
}
