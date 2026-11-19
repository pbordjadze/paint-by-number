import CoreGraphics
import Foundation
import os
import SwiftUI

/// The real work a library picture is of, as `library.json` records it (painting-company row
/// 120): who made it and when (`Sample.Provenance`), what it is made of, where it is kept, and
/// the pages to read next, the keeper's own catalog entry and, where the record names one, its
/// Wikipedia article. Nothing here is written by the app:
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
                place: text(record.place), wikipedia: link(record.wikipedia, host: "en.wikipedia.org"))
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
        let wikipedia: String?
    }
}

/// The Original (painting-company row 120): the page behind the last door after Finished
/// (`FinishedDoors`), shown only for a painting made from a library picture, and named as its
/// door is. It is the wall label the door draws: the picture, and under it one small placard set
/// as a museum sets one, the title, who made it and when, what it is made of and, last and most
/// present, where it hangs. A record without a place (a photograph) ends on its credit line
/// there; otherwise the credit is one faint line under the placard. The one prominent action is
/// the way to the keeper's own page, with Wikipedia's a plain link under it: both open in the
/// browser, and the app sends nothing. SideStore and Debug builds until Paul has seen it.
struct AboutPainting: View {
    let work: OriginalWork

    @Environment(\.dismiss) private var dismiss
    @State private var picture: CGImage?

    /// The picture's long side, in pixels: the sheet's width on an iPad, at 2×.
    nonisolated static let pixelSize = 1200
    /// The placard's widest: a label is a small card under a large picture, whatever the page.
    nonisolated static let placardWidth: CGFloat = 340

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 28) {
                        original(height: Self.pictureHeight(page: geo.size.height))
                        VStack(spacing: 10) {
                            placard
                            footnote
                        }
                        links
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    // In the middle of the sheet where it all fits, so no part of the page
                    // stands empty; from the top, scrolling, where it doesn't.
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
            }
            .background(Theme.paper)
            .navigationTitle(Text("The Original"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // In the words' color: the page's one tinted control is the catalog link, and
                    // the app's accent is gold on dark paper.
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .tint(.primary)
                }
            }
        }
        .task { picture = await SampleImages.shared.load(work.sample, maxPixelSize: Self.pixelSize) }
        .accessibilityIdentifier("about-painting")
    }

    /// The picture's room on a page so tall: more than half of it where the label and the links
    /// keep theirs in view under it (`labelAndLinks`: the ways out are what the page is for),
    /// and never less than a phone on its side can still read.
    nonisolated static func pictureHeight(page: CGFloat) -> CGFloat {
        max(180, min(page * 0.56, page - labelAndLinks))
    }

    /// About what the placard, its credit line, the links and the page's spacing take.
    nonisolated static let labelAndLinks: CGFloat = 420

    /// The picture itself, as the library has it: the placard under it names it for VoiceOver.
    @ViewBuilder
    private func original(height: CGFloat) -> some View {
        if let picture {
            Image(decorative: picture, scale: 1)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 3))
                .shadow(color: .black.opacity(0.22), radius: 16, y: 9)
                .frame(maxHeight: height)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: height)
        }
    }

    private var placard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(work.sample.title)
                .font(.display(.title2))
            Text(Acknowledgements.byline(work.provenance))
                .font(.body)
                .padding(.top, 3)
            if let medium = work.medium {
                Text(medium)
                    .font(.subheadline)
                    .foregroundStyle(Theme.quietInk)
                    .padding(.top, 10)
            }
            // Where it hangs, the label's last line: quieter than the title it answers.
            if let place = work.place {
                Text(place)
                    .font(.display(.headline, weight: .regular))
                    .padding(.top, 14)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: Self.placardWidth)
        // The card's shadow, not its words'.
        .background {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("about-label")
    }

    /// The keeper's credit line, faint under the label: a catalog number is no part of it.
    private var footnote: some View {
        Text(work.provenance.credit)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: Self.placardWidth - 36, alignment: .leading)
            .accessibilityIdentifier("about-credit")
    }

    /// The way out: the keeper's page, and Wikipedia's where the record names the work's own
    /// article.
    private var links: some View {
        VStack(spacing: 6) {
            Link(destination: work.source) {
                Label("See the Catalog Entry", systemImage: "arrow.up.right")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.signature)
            .controlSize(.large)
            .accessibilityHint(Text("Opens in your browser."))
            .accessibilityIdentifier("about-catalog")
            if let wikipedia = work.wikipedia {
                Link(destination: wikipedia) {
                    Text("Read on Wikipedia")
                        .font(.subheadline)
                        .underline()
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                // In the words' color, never the accent's: that is gold on dark paper.
                .tint(.primary)
                .accessibilityHint(Text("Opens in your browser."))
                .accessibilityIdentifier("about-wikipedia")
            }
        }
    }
}

#if DEBUG
/// Demo scenarios of the page, as the sheet the painting screen gives it, over the paper:
/// `about-painting` (The Great Wave, a record with every fact and a Wikipedia article;
/// `about-painting-dark` in dark appearance) and `about-photograph` (Earthrise, a record without
/// medium, place or article, whose placard ends on its credit line).
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
