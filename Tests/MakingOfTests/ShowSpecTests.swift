import Foundation
import Testing
@testable import MakingOf

@Suite struct ShowSpecTests {
    /// The shipped spec with `edit` applied, as bytes.
    private func edited(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        var json = try #require(try JSONSerialization.jsonObject(with: shippedSpecData()) as? [String: Any])
        edit(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// The shipped spec with `edit` applied to every step.
    private func editedSteps(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        try edited { json in
            var steps = json["steps"] as? [[String: Any]] ?? []
            for i in steps.indices {
                edit(&steps[i])
            }
            json["steps"] = steps
        }
    }

    private func editedCrew(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        try edited { json in
            var crew = json["crew"] as? [String: Any] ?? [:]
            edit(&crew)
            json["crew"] = crew
        }
    }

    @Test func shippedSpecDecodes() throws {
        let spec = try ShowSpec(json: shippedSpecData())
        #expect(spec.timing.intro == 0.6 && spec.timing.step == 2.5 && spec.timing.outro == 2.4)
        #expect(spec.steps.map(\.id) == ShowSpec.StepID.allCases)
        #expect(spec.steps.map(\.pose) == [.busy, .busy, .review, .review, .busy, .review])
        #expect(spec.steps[4].methods == ["Holistically-nested edge detection", "Informative drawings"])
        #expect(spec.steps.map(\.caption).allSatisfy { !$0.isEmpty })
        #expect(spec.steps[2].caption == "Choosing the paints")
        #expect(spec.cards.opacity == 0.62 && spec.cards.footnote == 0.55)
        #expect(spec.crew.pets == ["enchanted-workshop", "dinotopia", "snow-queen"])
        #expect(spec.crew.work == 0.6...0.95)
        #expect(spec.crew.traceRamp == ShowSpec.Ramp(up: 0.12, down: 0.16))
        #expect(spec.crew.bands == 3)
    }

    @Test func fixtureWasMadeFromTheShippedSpec() throws {
        // an edit to what the plan reads (the crew, the steps' order and poses, the timing) lands
        // here until the plan fixture is regenerated (see CrewPlan); captions and cards don't
        let shipped = try ShowSpec(json: shippedSpecData())
        let made = try PlanFixture.load().spec
        #expect(shipped.crew == made.crew)
        #expect(shipped.steps.map(\.id) == made.steps.map(\.id))
        #expect(shipped.steps.map(\.pose) == made.steps.map(\.pose))
        #expect(shipped.timing == made.timing)
    }

    @Test func badSpecsThrow() throws {
        let cases: [(String, Data)] = [
            ("another version", try edited { $0["version"] = 2 }),
            ("no version", try edited { $0["version"] = nil }),
            ("five steps", try edited { $0["steps"] = Array(($0["steps"] as? [Any] ?? []).dropLast()) }),
            ("seven steps", try edited { $0["steps"] = ($0["steps"] as? [Any] ?? []) + [["id": "extra", "caption": "x", "methods": ["x"], "pose": "busy"]] }),
            ("steps out of order", try edited { $0["steps"] = Array(($0["steps"] as? [Any] ?? []).reversed()) }),
            ("no caption", try editedSteps { $0["caption"] = nil }),
            ("an empty caption", try editedSteps { $0["caption"] = "" }),
            ("a blank caption", try editedSteps { $0["caption"] = "  \n" }),
            ("a number for a caption", try editedSteps { $0["caption"] = 3 }),
            ("a caption of a page", try editedSteps { $0["caption"] = String(repeating: "word ", count: 50) }),
            ("no footnote", try edited { $0["cards"] = ["opacity": 0.62] }),
            ("an invisible footnote", try edited { $0["cards"] = ["opacity": 0.62, "footnote": 0] }),
            ("a footnote bolder than bold", try edited { $0["cards"] = ["opacity": 0.62, "footnote": 1.5] }),
            ("a negative footnote", try edited { $0["cards"] = ["opacity": 0.62, "footnote": -0.5] }),
            ("a text for a footnote", try edited { $0["cards"] = ["opacity": 0.62, "footnote": "faint"] }),
            ("an unknown key in the cards", try edited { $0["cards"] = ["opacity": 0.62, "footnote": 0.55, "shadow": 1] }),
            ("an unknown key in a step", try editedSteps { $0["subtitle"] = "x" }),
            ("no methods", try editedSteps { $0["methods"] = [String]() }),
            ("an unknown pose", try editedSteps { $0["pose"] = "dancing" }),
            ("a negative time", try edited { $0["timing"] = ["intro": 0.6, "step": -2.5, "outro": 2.4] }),
            ("a zero time", try edited { $0["timing"] = ["intro": 0, "step": 2.5, "outro": 2.4] }),
            ("an enormous time", try edited { $0["timing"] = ["intro": 0.6, "step": 1e9, "outro": 2.4] }),
            ("an unknown key", try edited { $0["extra"] = 1 }),
            ("an unknown key in the crew", try editedCrew { $0["wlak"] = 2.4 }),
            ("a missing key in the crew", try editedCrew { $0["walk"] = nil }),
            ("a text for a number", try editedCrew { $0["walk"] = "fast" }),
            ("a fraction for a count", try editedCrew { $0["bands"] = 2.5 }),
            ("no bands", try editedCrew { $0["bands"] = 0 }),
            ("a zero walking pace", try editedCrew { $0["walk"] = 0 }),
            ("a negative length", try editedCrew { $0["stride"] = -1.5 }),
            ("work times the wrong way round", try editedCrew { $0["work"] = [0.95, 0.6] }),
            ("three work times", try editedCrew { $0["work"] = [0.6, 0.8, 0.95] }),
            ("the same pet twice", try editedCrew { $0["pets"] = ["dinotopia", "dinotopia"] }),
            ("no pets", try editedCrew { $0["pets"] = [String]() }),
            ("a margin of half the picture", try editedCrew { $0["margin"] = 0.5 }),
            ("not json", Data("{".utf8)),
            ("not an object", Data("[1]".utf8)),
            ("nothing", Data()),
            ("far too much", Data(repeating: 0x20, count: ShowSpec.maximumBytes + 1)),
        ]
        for (what, data) in cases {
            #expect(throws: (any Error).self, "\(what) should throw") { try ShowSpec(json: data) }
        }
    }

    @Test func theErrorNamesTheKey() throws {
        do {
            _ = try ShowSpec(json: editedCrew { $0["wlak"] = 2.4 })
            Issue.record("decoded")
        } catch let error as DecodingError {
            #expect("\(error)".contains("wlak"))
        }
    }

    @Test func aSensibleEditStillDecodes() throws {
        let data = try edited { json in
            json["cards"] = ["opacity": 0.5, "footnote": 1]
            var crew = json["crew"] as? [String: Any] ?? [:]
            crew["walk"] = 3.0
            crew["pets"] = ["dinotopia"]
            json["crew"] = crew
        }
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var steps = json["steps"] as? [[String: Any]] ?? []
        for i in steps.indices {
            steps[i]["pose"] = "review"
            steps[i]["caption"] = "Painting"
        }
        json["steps"] = steps
        let spec = try ShowSpec(json: JSONSerialization.data(withJSONObject: json))
        #expect(spec.steps.allSatisfy { $0.pose == .review && $0.caption == "Painting" })
        #expect(spec.cards.footnote == 1)
        #expect(spec.crew.walk == 3 && spec.crew.pets == ["dinotopia"])
    }

    @Test func aFaintFootnoteIsStillAFootnote() throws {
        let data = try edited { $0["cards"] = ["opacity": 0.62, "footnote": 0.001] }
        #expect(try ShowSpec(json: data).cards.footnote == 0.001)
    }
}
