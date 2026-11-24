#if UNRELEASED
import Foundation
import Testing
@testable import PaintByNumber

/// One Big Sheet's terms (painting-company row 380): the bundled text is there and reads as the page's blocks.
@MainActor
struct BigSheetTermsTests {
    @Test func theBundledTermsLoadWithTheirRefundSection() throws {
        let text = try #require(BigSheetTerms.text())
        let blocks = BigSheetTerms.blocks(text)
        #expect(blocks.first == .title("Terms of Sale and Refunds"))
        #expect(blocks.contains(.heading("3. Refunds and reprints")))
        #expect(blocks.contains { if case .bullet = $0 { true } else { false } })
    }

    @Test func aBulletsWrappedLineJoinsIt() {
        let blocks = BigSheetTerms.blocks("## Head\n\n- one\n  two\n\nA paragraph\non two lines.")
        #expect(blocks == [.heading("Head"), .bullet("one two"), .paragraph("A paragraph on two lines.")])
    }
}
#endif
