import Foundation
import os
import PaintCore
import SwiftUI
import UIKit

/// What Print… hands the system's print dialog (painting-company row 240): the printable
/// template's PDF (`PDFExporter.document`: the template, on
/// several sheets when it is detailed, then the color key), and the name of its print job.
/// Printing makes no painting, so it takes no free painting, and a painting someone sent prints
/// as any other.
nonisolated struct TemplatePrintJob: Identifiable, Sendable {
    let id = UUID()
    /// "Irises Template", as the PDF's file is named (`ArtworkExporter.templateName`).
    let name: String
    let pdf: Data

    /// A gallery card's: the saved painting's template, as `PrintableTemplateFile` writes it.
    @concurrent
    static func saved(store: ArtworkStore, artwork: Artwork, paper: PDFExporter.Paper) async throws -> TemplatePrintJob {
        try TemplatePrintJob(title: artwork.title, pdf: ArtworkExporter.templatePDF(store: store, artwork: artwork, paper: paper))
    }

    /// An open painting's, from its session: the template on screen with the paint names it
    /// shows (`PaintingSession.colorNicknames`), whatever is painted on it.
    @concurrent
    static func open(
        template: Template, title: String, nicknames: [String?], paper: PDFExporter.Paper
    ) async throws -> TemplatePrintJob {
        try TemplatePrintJob(
            title: title, pdf: PDFExporter.document(for: template, title: title, paper: paper, nicknames: nicknames))
    }

    /// Print's preview's: the pages of the layout the painter chose (`PrintPreviewSheet`).
    @concurrent
    static func open(
        template: Template, title: String, nicknames: [String?], layout: PDFExporter.Layout
    ) async throws -> TemplatePrintJob {
        try TemplatePrintJob(
            title: title, pdf: PDFExporter.document(for: template, title: title, layout: layout, nicknames: nicknames))
    }

    private init(title: String, pdf: Data) throws {
        // `PDFExporter.document` is empty when no PDF could be begun: nothing to print.
        guard !pdf.isEmpty else { throw ArtworkExporter.ExportError.renderFailed }
        name = ArtworkExporter.templateName(title: title)
        self.pdf = pdf
    }
}

/// Presents the system's print dialog for a job as soon as there is one, from the view it lies
/// behind (an iPad's dialog points at it), and reports when the dialog closes, printed or not.
/// The print counterpart of `ActivityShareSheet`.
struct PrintSheet: UIViewControllerRepresentable {
    let job: TemplatePrintJob?
    /// Called with the job's id once its dialog closes, or when it couldn't open. A job is let
    /// go by its id: a newer one may have taken its place.
    let onFinish: (TemplatePrintJob.ID) -> Void
    /// Called before `onFinish` when the job went to the printer (not when the dialog was
    /// cancelled): Print's preview then closes too.
    var onPrinted: ((TemplatePrintJob.ID) -> Void)? = nil

    /// False where the device can't print at all: Print… is then not offered.
    static var isAvailable: Bool { UIPrintInteractionController.isPrintingAvailable }

    /// Whether the dialog has come up for this job: one that never did (the view it hangs from
    /// isn't on screen) is dropped by whoever made it.
    static func hasShown(_ job: TemplatePrintJob.ID) -> Bool { Controller.shownJob == job }

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.job = job
        controller.onFinish = onFinish
        controller.onPrinted = onPrinted
        // It lies behind More for as long as a painting is open: without a job, an update (one
        // comes with every fill) does nothing more.
        guard job != nil else { return }
        // Never inside SwiftUI's update pass: it can race the dialog's own presentation.
        Task { @MainActor [weak controller] in controller?.presentIfNeeded() }
    }

    final class Controller: UIViewController {
        var job: TemplatePrintJob?
        var onFinish: ((TemplatePrintJob.ID) -> Void)?
        var onPrinted: ((TemplatePrintJob.ID) -> Void)?
        /// The system has one print dialog (`UIPrintInteractionController.shared`), so what it
        /// shows is kept for every controller: the job it last came up for, which is never
        /// shown twice (a view laid out again has a new controller and, for a moment, the job
        /// that just closed), and whether it is up.
        static private(set) var shownJob: TemplatePrintJob.ID?
        private static var isShowing = false
        /// What the dialog on screen calls as it closes: its job's own closure, not a
        /// controller's, since a view laid out again meanwhile has another controller and the
        /// job must still be let go.
        private static var finishShowing: ((TemplatePrintJob.ID) -> Void)?
        private static var printedShowing: ((TemplatePrintJob.ID) -> Void)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            Task { @MainActor [weak self] in self?.presentIfNeeded() }
        }

        func presentIfNeeded() {
            guard let job, job.id != Self.shownJob, let view = viewIfLoaded, view.window != nil else { return }
            // Another job while a dialog counts as up: Print… was asked for again, which no one
            // can do under a dialog. The system took it down without a word (the app left the
            // foreground, an iPad's popover lost its card), so it is closed here.
            if Self.isShowing, let stale = Self.shownJob {
                UIPrintInteractionController.shared.dismiss(animated: false)
                Self.closed(stale)
            }
            let id = job.id
            Self.shownJob = id
            Self.isShowing = true
            Self.finishShowing = onFinish
            Self.printedShowing = onPrinted
            let info = UIPrintInfo.printInfo()
            info.outputType = .general
            info.jobName = job.name
            let printer = UIPrintInteractionController.shared
            printer.printInfo = info
            printer.printingItem = job.pdf
            let completion = Self.completion { printed in Controller.closed(id, printed: printed) }
            // An iPad's dialog hangs from this view; an iPhone's (a Duo's too) is the system's sheet.
            let shown = traitCollection.userInterfaceIdiom == .pad
                ? printer.present(from: view.bounds, in: view, animated: true, completionHandler: completion)
                : printer.present(animated: true, completionHandler: completion)
            if !shown {
                Log.library.error("The print dialog didn't open")
                Self.closed(id)
            }
        }

        /// The job's dialog is gone: the shared controller lets go of the PDF, then the job is
        /// let go. Once a job: a completion that comes after its dialog was closed here, a newer
        /// one perhaps up, changes nothing.
        private static func closed(_ id: TemplatePrintJob.ID, printed: Bool = false) {
            guard isShowing, shownJob == id else { return }
            isShowing = false
            UIPrintInteractionController.shared.printingItem = nil
            let finish = finishShowing, done = printedShowing
            finishShowing = nil
            printedShowing = nil
            if printed { done?(id) }
            finish?(id)
        }

        /// Built outside the main actor: UIKit may call it on any thread.
        nonisolated private static func completion(
            _ finish: @escaping @MainActor @Sendable (Bool) -> Void
        ) -> UIPrintInteractionController.CompletionHandler {
            { _, completed, _ in Task { @MainActor in finish(completed) } }
        }
    }
}
