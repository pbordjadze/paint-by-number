#if DEBUG
import PaintCore
import SwiftUI

/// Demo scenarios of Print's preview (`PrintPreviewSheet`, shared with Paint by Mosaic), as the
/// sheet a painting's More gives it, over the paper, on The Great Wave: `print-preview` (with
/// `-dark`, `-long-text`), `print-preview-painted` (Painted chosen) and `print-preview-sheets` (the
/// next size up, on several sheets).
struct PrintPreviewDemo: View {
    let scenario: String
    @State private var request: PrintPreviewRequest?

    var body: some View {
        Theme.paper.ignoresSafeArea()
            .sheet(item: $request) { request in
                PrintPreviewSheet(
                    request: request, showsPainted: scenario.hasPrefix("print-preview-painted"),
                    across: scenario.hasPrefix("print-preview-sheets") ? 2 : nil)
                    .pageSizedOnPad()
            }
            .task {
                guard let sample = Sample.named("great-wave"),
                      let draft = try? await ArtworkFactory.draft(sample: sample, photoMaxPixelSize: 560)
                else { return }
                request = PrintPreviewRequest(template: draft.template, title: sample.title, nicknames: [])
            }
    }
}
#endif
