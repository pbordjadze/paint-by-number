import Foundation
import Testing
@testable import MakingOf

@Suite struct CardsTests {
    /// The entries of `ACKNOWLEDGEMENTS.md` (the `###` headings, with the lines that follow), read
    /// through `#filePath` like the spec. The app's `Acknowledgements` has the same entries.
    private struct Entry {
        var name: String
        var section: String
        var body: [String]
    }

    private func entries() throws -> [Entry] {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: repo.appendingPathComponent("ACKNOWLEDGEMENTS.md"), encoding: .utf8)
        var found: [Entry] = []
        var section = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("## ") {
                section = String(line.dropFirst(3))
            } else if line.hasPrefix("### ") {
                found.append(Entry(name: String(line.dropFirst(4)), section: section, body: []))
            } else if !found.isEmpty && !line.hasPrefix("## ") {
                found[found.count - 1].body.append(line)
            }
        }
        return found
    }

    /// `authors, "title", year`: the credit line a card prints.
    private func creditLine(_ entry: Entry) -> String? {
        entry.body.last { $0.range(of: #".+, ".+", \d{4}$"#, options: .regularExpression) != nil }
    }

    @Test func eachMethodNamesExactlyOneEntryByItsExactName() throws {
        let spec = try ShowSpec(json: shippedSpecData())
        let all = try entries()
        for step in spec.steps {
            for method in step.methods {
                // exact and case sensitive: "Informative drawings" (the method) is not "Informative Drawings" (the model)
                let named = all.filter { $0.name == method }
                #expect(named.count == 1, "\(method) names \(named.count) entries")
                #expect(named.first?.section == "Methods", "\(method) is in \(named.first?.section ?? "no section")")
                #expect(named.first.flatMap(creditLine) != nil, "\(method) has no credit line")
            }
        }
    }

    @Test func theModelAndTheMethodWithTheSameNameAreTwoEntries() throws {
        let all = try entries()
        #expect(all.filter { $0.name.lowercased() == "informative drawings" }.map(\.section).sorted() == ["Methods", "Models"])
        let spec = try ShowSpec(json: shippedSpecData())
        #expect(spec.steps[4].methods.contains("Informative drawings") && !spec.steps[4].methods.contains("Informative Drawings"))
    }

    @Test func aCardCarriesTheStepsWordsAndItsOpacities() throws {
        let show = try FieldFixture.small
        let spec = try SmallShow().spec
        let t = spec.timing.intro + 4 * spec.timing.step + spec.timing.step / 2
        let card = try #require(show.frame(at: t).card)
        #expect(card == CardDraw(
            step: 4, caption: "Drawing the lines", methods: ["Holistically-nested edge detection", "Informative drawings"],
            opacity: spec.cards.opacity, footnoteOpacity: spec.cards.opacity * spec.cards.footnote))
        #expect(card.footnoteOpacity < card.opacity)
    }
}
