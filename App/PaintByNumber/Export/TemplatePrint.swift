import Foundation
import os
import PaintCore
import SwiftUI
import UIKit

/// What Print… hands the system's print dialog (painting-company row 240): the printable
/// template, the very PDF Print Template… shares (`PDFExporter.document`: the template, on
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
    /// Called once the dialog closes, or when it couldn't open.
    let onFinish: () -> Void

    /// False where the device can't print at all: Print… is then not offered.
    static var isAvailable: Bool { UIPrintInteractionController.isPrintingAvailable }

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.job = job
        controller.onFinish = onFinish
        // It lies behind More for as long as a painting is open: without a job, an update (one
        // comes with every fill) does nothing more.
        guard job != nil else { return }
        // Never inside SwiftUI's update pass: it can race the dialog's own presentation.
        Task { @MainActor [weak controller] in controller?.presentIfNeeded() }
    }

    final class Controller: UIViewController {
        var job: TemplatePrintJob?
        var onFinish: (() -> Void)?
        private var presentedJob: TemplatePrintJob.ID?
        /// The system has one print dialog (`UIPrintInteractionController.shared`): while it is
        /// up, nothing sets it up again.
        private static var isShowing = false
        /// What the dialog on screen calls as it closes: its job's own closure, not a
        /// controller's, since a view laid out again meanwhile has another controller and the
        /// job must still be let go.
        private static var finishShowing: (() -> Void)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            Task { @MainActor [weak self] in self?.presentIfNeeded() }
        }

        func presentIfNeeded() {
            guard let job, job.id != presentedJob, !Self.isShowing, let view = viewIfLoaded, view.window != nil
            else { return }
            presentedJob = job.id
            Self.isShowing = true
            Self.finishShowing = onFinish
            let info = UIPrintInfo.printInfo()
            info.outputType = .general
            info.jobName = job.name
            let printer = UIPrintInteractionController.shared
            printer.printInfo = info
            printer.printingItem = job.pdf
            let completion = Self.completion { Controller.closed() }
            // An iPad's dialog hangs from this view; an iPhone's (a Duo's too) is the system's sheet.
            let shown = traitCollection.userInterfaceIdiom == .pad
                ? printer.present(from: view.bounds, in: view, animated: true, completionHandler: completion)
                : printer.present(animated: true, completionHandler: completion)
            if !shown {
                Log.library.error("The print dialog didn't open")
                Self.closed()
            }
        }

        /// The dialog is gone: the shared controller lets go of the PDF, then the job is let go.
        private static func closed() {
            isShowing = false
            UIPrintInteractionController.shared.printingItem = nil
            let finish = finishShowing
            finishShowing = nil
            finish?()
        }

        /// Built outside the main actor: UIKit may call it on any thread.
        nonisolated private static func completion(
            _ finish: @escaping @MainActor @Sendable () -> Void
        ) -> UIPrintInteractionController.CompletionHandler {
            { _, _, _ in Task { @MainActor in finish() } }
        }
    }
}
