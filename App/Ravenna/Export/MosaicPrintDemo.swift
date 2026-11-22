#if DEBUG
import Foundation
import MosaicCore
import MosaicKit
import os
import PaintCore
import SwiftUI

/// Demo scenarios of Print's preview (`PrintPreviewSheet`, shared with Paint by Moonlight) on a
/// mosaic's sheet, as a card's or the mosaic's Print… opens it, over the paper: the bundled Young
/// Woman with a Gilded Wreath at standard detail (`Resources/Mosaics`), its paints under their
/// names. `print-preview` (blank, as it prints) and `print-preview-painted` (Painted chosen).
struct MosaicPrintDemo: View {
    let scenario: String
    @State private var request: PrintPreviewRequest?

    var body: some View {
        Theme.paper.ignoresSafeArea()
            .sheet(item: $request) { request in
                PrintPreviewSheet(request: request, showsPainted: scenario.hasPrefix("print-preview-painted"))
                    .pageSizedOnPad()
            }
            .task { request = await Self.request() }
    }

    /// The bundled mosaic's template, titled and named as its painting would be.
    @concurrent
    private static func request() async -> PrintPreviewRequest? {
        guard let url = Bundle.ravenna.url(forResource: "young-woman-gilded-wreath-standard", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let mosaic = try? JSONDecoder().decode(Mosaic.self, from: data),
              let template = try? MosaicCore.template(of: mosaic)
        else {
            Log.demo.error("demo: the mosaic made no template to print")
            return nil
        }
        let seed = ColorNickname.seed(for: UUID(uuidString: "5A1E0547-0000-4000-8000-000000000547")!)
        let nicknames = ColorNameText.nicknames(for: template.palette, seed: seed, version: ColorNickname.currentVersion)
        return PrintPreviewRequest(template: template, title: "Young Woman with a Gilded Wreath", nicknames: nicknames)
    }
}
#endif
