#if DEBUG
import PaintCore
import SwiftUI

/// Demo scenarios of Print's preview (`PrintPreviewSheet`, shared with Paint by Mosaic), as the
/// sheet a painting's More gives it, over the paper, on The Great Wave: `print-preview` (with
/// `-dark`, `-long-text`), `print-preview-painted` (Painted chosen), `print-preview-sheets` (the
/// next size up, on several sheets), and two of the layers' (painting-company row 370):
/// `print-preview-no-numbers` (a coloring page) and `print-preview-hints` (Color Hints on).
/// In SideStore and Debug builds One Big Sheet (painting-company row 380) as Print's preview
/// pushes it, on the stub's sandbox price: `print-big-sheet` (with `-dark`, `-long-text`) and
/// its test order placed (`-placed`).
struct PrintPreviewDemo: View {
    let scenario: String
    @State private var request: PrintPreviewRequest?

    var body: some View {
        Theme.paper.ignoresSafeArea()
            .sheet(item: $request) { request in
                #if UNRELEASED
                if scenario.hasPrefix("print-big-sheet") {
                    NavigationStack {
                        BigSheetView(
                            request: request, layout: PDFExporter.Layout(paper: .default(for: Locale.current.region)),
                            placed: scenario.hasPrefix("print-big-sheet-placed") ? "ord_828417" : nil)
                    }
                    .pageSizedOnPad()
                } else {
                    preview(request)
                }
                #else
                preview(request)
                #endif
            }
            .task {
                guard let sample = Sample.named("great-wave"),
                      let draft = try? await ArtworkFactory.draft(sample: sample, photoMaxPixelSize: 560)
                else { return }
                request = PrintPreviewRequest(template: draft.template, title: sample.title, nicknames: [])
            }
    }

    private func preview(_ request: PrintPreviewRequest) -> some View {
        PrintPreviewSheet(
            request: request, showsPainted: scenario.hasPrefix("print-preview-painted"),
            across: scenario.hasPrefix("print-preview-sheets") ? 2 : nil,
            numbers: !scenario.hasPrefix("print-preview-no-numbers"),
            colorHints: scenario.hasPrefix("print-preview-hints"))
            .pageSizedOnPad()
    }
}
#endif
