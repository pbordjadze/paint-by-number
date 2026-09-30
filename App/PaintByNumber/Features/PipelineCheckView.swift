import PaintCore
import SwiftUI

/// Temporary bring-up screen: generates a template from a bundled sample and shows it,
/// proving the pipeline links and runs on device.
struct PipelineCheckView: View {
    @State private var report = "Generating…"
    @State private var preview: CGImage?

    var body: some View {
        VStack(spacing: 16) {
            if let preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 12))
            }
            Text(report)
                .font(.footnote.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .task {
            await run()
            DemoMode.markReady()
        }
    }

    private func run() async {
        guard let url = Bundle.main.url(forResource: "parrots", withExtension: "jpg") else {
            report = "Missing sample"
            return
        }
        do {
            let result = try await Self.generate(url: url)
            preview = result.image
            report = result.report
        } catch {
            report = "Failed: \(error)"
        }
    }

    @concurrent
    private static func generate(url: URL) async throws -> (image: CGImage?, report: String) {
        let photo = try PhotoLoader.load(url: url, maxPixelSize: 2048)
        let output = try TemplateGenerator().generate(from: photo)
        let t = output.template
        var pixels = [UInt8](repeating: 255, count: t.width * t.height * 4)
        for i in 0..<(t.width * t.height) {
            let c = t.palette[Int(t.regions[Int(t.regionMap.storage[i])].colorIndex)].rgb
            pixels[i * 4] = UInt8(c.x * 255); pixels[i * 4 + 1] = UInt8(c.y * 255); pixels[i * 4 + 2] = UInt8(c.z * 255)
        }
        let image = PhotoLoader.cgImage(from: RGBAImage(width: t.width, height: t.height, pixels: pixels, colorSpace: t.colorSpace))
        let lines = ["\(t.width)×\(t.height) · \(t.palette.count) colors · \(t.regions.count) regions"]
            + output.timings.map(\.description)
        return (image, lines.joined(separator: "\n"))
    }
}
