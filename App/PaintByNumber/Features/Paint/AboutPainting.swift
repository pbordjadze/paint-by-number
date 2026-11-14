#if UNRELEASED
import CoreGraphics
import Foundation
import os
import SwiftUI

/// The real work a library picture is of, as `library.json` records it (painting-company row
/// 120): who made it and when (`Sample.Provenance`), what it is made of, where it is kept, the
/// title its keeper catalogs it under, and the pages to read next, the keeper's own catalog entry
/// and, where the record names one, its Wikipedia article. Nothing here is written by the app:
/// every line is the record's (`docs/picture-library.md` › The record), and a fact the record
/// lacks is left out.
nonisolated struct OriginalWork: Identifiable, Hashable, Sendable {
    let sample: Sample
    let provenance: Sample.Provenance
    /// The picture's page at the museum or agency that keeps it (the record's `source`).
    let source: URL
    /// As the source words it ("Oil on canvas"), its first letter a capital.
    let medium: String?
    let place: String?
    /// The source's own title, where the library's is shorter (the record's `work_title`).
    let catalogTitle: String?
    let wikipedia: URL?

    var id: String { sample.id }

    /// The work behind the library picture a painting was made from (`Artwork.sampleName`); nil
    /// for a painter's own photo, and for a picture the library no longer offers.
    static func of(_ sampleName: String?) -> OriginalWork? {
        sampleName.flatMap { all[$0] }
    }

    /// The library's works, by picture id.
    static let all: [String: OriginalWork] = {
        guard let url = Bundle.main.url(forResource: "library", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [:] }
        return listed(in: data, samples: Sample.all)
    }()

    /// The works a `library.json` records, of the pictures in `samples`. A picture without an
    /// https page to open has none; a Wikipedia link that isn't an article of the English
    /// Wikipedia is dropped.
    static func listed(in data: Data, samples: [Sample]) -> [String: OriginalWork] {
        let records: [Record]
        do {
            records = try JSONDecoder().decode([Record].self, from: data)
        } catch {
            Log.library.fault("library.json's sources don't decode: \(String(describing: error), privacy: .public)")
            return [:]
        }
        let pictures = Dictionary(samples.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var works: [String: OriginalWork] = [:]
        for record in records {
            guard let sample = pictures[record.id], let provenance = sample.provenance,
                  let source = link(record.source) else { continue }
            works[record.id] = OriginalWork(
                sample: sample, provenance: provenance, source: source, medium: sentence(record.medium),
                place: text(record.place), catalogTitle: text(record.workTitle),
                wikipedia: link(record.wikipedia, host: "en.wikipedia.org"))
        }
        return works
    }

    /// An https address, on `host` where one is asked for.
    private static func link(_ string: String?, host: String? = nil) -> URL? {
        guard let string, let url = URL(string: string), url.scheme == "https", let found = url.host(), !found.isEmpty,
              host == nil || found == host else { return nil }
        return url
    }

    private static func text(_ string: String?) -> String? {
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Museums write a medium either way ("Oil on canvas", "oil on fabric"): on the page each
    /// starts with a capital.
    private static func sentence(_ string: String?) -> String? {
        text(string).map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    /// The fields of a `library.json` record this page reads; `Sample` reads the picture's own.
    private struct Record: Decodable {
        let id: String
        let source: String?
        let medium: String?
        let place: String?
        let workTitle: String?
        let wikipedia: String?

        private enum CodingKeys: String, CodingKey {
            case id, source, medium, place, wikipedia
            case workTitle = "work_title"
        }
    }
}

/// About this painting (painting-company row 120): the page behind The Original, the last door
/// after Finished (`FinishedDoors`), shown only for a painting made from a library picture. The
/// picture, its title, who made it and when, what the library records of the work, and the way
/// out to the pages its keepers wrote: the links open in the browser, and the app sends nothing.
/// SideStore and Debug builds until Paul has seen it.
struct AboutPainting: View {
    let work: OriginalWork

    @Environment(\.dismiss) private var dismiss
    @State private var picture: CGImage?

    /// The picture's long side, in pixels: the page's width on an iPad, at 2×.
    nonisolated static let pixelSize = 1200

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    original
                    heading
                    facts
                    links
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .tint(Theme.signature)
                }
            }
        }
        .task { picture = await SampleImages.shared.load(work.sample, maxPixelSize: Self.pixelSize) }
        .accessibilityIdentifier("about-painting")
    }

    private var title: Text {
        switch work.provenance.kind {
        case .painting: Text("About This Painting")
        case .photograph: Text("About This Photograph")
        }
    }

    /// The picture itself, as the library has it: the title beside it names it for VoiceOver.
    @ViewBuilder private var original: some View {
        if let picture {
            Image(decorative: picture, scale: 1)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 4))
                .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
                .frame(maxHeight: 340)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: 240)
        }
    }

    private var heading: some View {
        VStack(spacing: 6) {
            Text(work.sample.title)
                .font(.display(.title))
            Text(Acknowledgements.byline(work.provenance))
                .font(.title3)
                .foregroundStyle(Theme.quietInk)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private struct Fact: Identifiable {
        let id: String
        let label: Text
        let value: String
    }

    /// What the record has, in a museum label's order; the credit line always.
    private var rows: [Fact] {
        var rows: [Fact] = []
        if let medium = work.medium { rows.append(Fact(id: "medium", label: Text("Medium"), value: medium)) }
        if let place = work.place { rows.append(Fact(id: "place", label: Text("Where It’s Kept"), value: place)) }
        if let catalogTitle = work.catalogTitle {
            rows.append(Fact(id: "catalog-title", label: Text("Cataloged As"), value: catalogTitle))
        }
        rows.append(Fact(id: "credit", label: Text("Credit"), value: work.provenance.credit))
        return rows
    }

    private var facts: some View {
        let shown = rows
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { fact in
                VStack(alignment: .leading, spacing: 3) {
                    fact.label
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(fact.value)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("about-\(fact.id)")
                if fact.id != shown.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// The way out: what the painter reads next is the keeper's page, and Wikipedia's where the
    /// record names the work's own article.
    private var links: some View {
        VStack(spacing: 12) {
            Link(destination: work.source) {
                Label("See the Catalog Entry", systemImage: "arrow.up.right")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.signature)
            .accessibilityHint(Text("Opens in your browser."))
            .accessibilityIdentifier("about-catalog")
            if let wikipedia = work.wikipedia {
                Link(destination: wikipedia) {
                    Label("Read on Wikipedia", systemImage: "book")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.glass)
                .accessibilityHint(Text("Opens in your browser."))
                .accessibilityIdentifier("about-wikipedia")
            }
        }
        .controlSize(.large)
    }
}

#if DEBUG
/// Demo scenarios of the page, as a sheet over the paper: `about-painting` (The Great Wave, a
/// record with every fact and a Wikipedia article; `about-painting-dark` in dark appearance) and
/// `about-photograph` (Earthrise, a record without medium, place or article).
struct AboutPaintingDemo: View {
    let scenario: String

    var body: some View {
        let work = OriginalWork.of(scenario.hasPrefix("about-photograph") ? "earthrise" : "great-wave")
        Theme.paper.ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                if let work { AboutPainting(work: work).pageSizedOnPad() }
            }
            .task {
                guard let work else { return }
                // The page's own picture, so the screenshot has it.
                _ = await SampleImages.shared.load(work.sample, maxPixelSize: AboutPainting.pixelSize)
                DemoMode.markReady()
            }
    }
}
#endif
#endif
