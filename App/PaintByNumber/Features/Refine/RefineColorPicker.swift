import SwiftUI
import UIKit

/// The system color picker for an area's card, presented by the card itself (`RefineAreaCard`'s
/// Only This Area row) rather than by SwiftUI's `ColorPicker`, whose well alone opened it: the
/// whole row is the button VoiceOver reads it as (QA, November 7). A popover from the row's well
/// on iPad; on iPhone a sheet at half height over the card, the picture left undimmed above it,
/// so the color is seen landing on the area as it is picked, as Notes' and Freeform's pickers do.
struct RefineColorPickerPresenter: UIViewRepresentable {
    @Binding var isPresented: Bool
    let title: String
    /// The color the picker opens on.
    let color: UIColor
    /// Each color the picker gives, continuously while it moves.
    let picked: (UIColor) -> Void
    /// The picker closed.
    let finished: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.picked = picked
        coordinator.finished = { [weak coordinator] in
            coordinator?.picker = nil
            isPresented = false
            finished()
        }
        if isPresented, coordinator.picker == nil {
            coordinator.present(from: view, title: title, color: color)
        } else if !isPresented, let picker = coordinator.picker {
            coordinator.picker = nil
            picker.dismiss(animated: true)
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        // The card went (its popover closed, Select's bar changed): so does its picker.
        coordinator.picker?.dismiss(animated: true)
        coordinator.picker = nil
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate, UIPopoverPresentationControllerDelegate,
        UISheetPresentationControllerDelegate {
        var picker: UIColorPickerViewController?
        var picked: (UIColor) -> Void = { _ in }
        var finished: () -> Void = {}

        func present(from view: UIView, title: String, color: UIColor) {
            guard var host = Self.controller(of: view) else {
                // Not during the update that asked.
                Task { @MainActor in self.finished() }
                return
            }
            while let shown = host.presentedViewController, !shown.isBeingDismissed { host = shown }
            let picker = UIColorPickerViewController()
            picker.title = title
            picker.supportsAlpha = false
            picker.selectedColor = color
            picker.delegate = self
            // The window's size class: content inside a popover (the area's card on iPad) reports
            // compact, which would give the iPad the phone's sheet.
            if (view.window?.traitCollection ?? host.traitCollection).horizontalSizeClass == .compact {
                // A phone: half the screen, the picture above it undimmed, as a popover's
                // adaptation left it dimmed and covering most of the screen.
                picker.modalPresentationStyle = .pageSheet
                if let sheet = picker.sheetPresentationController {
                    sheet.detents = [.custom(identifier: Self.lower) { $0.maximumDetentValue * 0.5 }, .large()]
                    sheet.largestUndimmedDetentIdentifier = Self.lower
                    sheet.prefersGrabberVisible = true
                    sheet.delegate = self
                }
            } else {
                picker.modalPresentationStyle = .popover
                if let popover = picker.popoverPresentationController {
                    popover.sourceView = view
                    popover.sourceRect = view.bounds
                    popover.delegate = self
                }
            }
            self.picker = picker
            host.present(picker, animated: true)
        }

        /// The sheet's lower height on iPhone: half the screen, the picture above it.
        static let lower = UISheetPresentationController.Detent.Identifier("refine.colorPicker.lower")

        /// The view controller `view` is in.
        private static func controller(of view: UIView) -> UIViewController? {
            var responder: UIResponder? = view
            while let next = responder?.next {
                if let controller = next as? UIViewController { return controller }
                responder = next
            }
            return nil
        }

        func colorPickerViewController(
            _ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool
        ) {
            picked(color)
        }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            guard viewController === picker else { return }
            finished()
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            guard presentationController.presentedViewController === picker else { return }
            finished()
        }
    }
}
