import SwiftUI
import UIKit

/// Settings › Advanced › Feedback: Copy Settings, Share with a Note, Paste Settings and Reset
/// All.
struct AdvancedFeedbackSection: View {
    let model: AdvancedSettingsModel
    @State private var isSharing = false
    @State private var isConfirmingReset = false
    @State private var copied = false
    @State private var pasted = false
    @State private var pasteFailed = false

    var body: some View {
        Section {
            Button(action: copy) {
                if copied {
                    SwiftUI.Label("Copied", systemImage: "checkmark")
                } else {
                    SwiftUI.Label("Copy Settings", systemImage: "doc.on.doc")
                }
            }
            .accessibilityIdentifier("advanced-copy")
            Button {
                isSharing = true
            } label: {
                SwiftUI.Label("Share with a Note…", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("advanced-share")
            .sheet(isPresented: $isSharing) {
                AdvancedShareSheet(model: model)
            }
            pasteRow
            Button(role: .destructive) {
                isConfirmingReset = true
            } label: {
                SwiftUI.Label("Reset All Settings", systemImage: "arrow.counterclockwise")
            }
            .disabled(model.isLineArtDefault && model.isAppearanceDefault && model.isTuningDefault)
            .accessibilityIdentifier("advanced-reset-all")
            .confirmationDialog("Reset All Advanced Settings?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                Button("Reset All", role: .destructive) {
                    FeedbackEngine.shared.selectionChanged()
                    withAnimation(.snappy) { model.resetAll() }
                }
            } message: {
                Text("Line art, line appearance and the pipeline go back to their defaults.")
            }
        } header: {
            Text(String(localized: "advanced.section.feedback", defaultValue: "Feedback",
                        comment: "Settings › Advanced: header of the section for sending the settings to the developer and resetting them"))
        } footer: {
            Text("Copies include the picture, the preview’s numbers and every setting, so what you saw can be made again. Paste takes the settings in copied text, from another device or a preset.")
        }
    }

    /// Paste Settings: the system paste button (no permission prompt) beside what it does. The
    /// button is enabled while the clipboard holds text.
    private var pasteRow: some View {
        HStack(spacing: 12) {
            if pasted {
                SwiftUI.Label("Pasted", systemImage: "checkmark")
            } else {
                SwiftUI.Label("Paste Settings", systemImage: "doc.on.clipboard")
            }
            Spacer(minLength: 8)
            PasteButton(payloadType: String.self) { texts in paste(texts) }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(Theme.signature)
                .accessibilityIdentifier("advanced-paste")
        }
        .alert("Couldn’t Read Settings", isPresented: $pasteFailed) {} message: {
            Text("The pasted text holds no Paint by Moonlight settings.")
        }
    }

    private func paste(_ texts: [String]) {
        guard let imported = texts.lazy.compactMap(AdvancedReport.settings(in:)).first else {
            pasteFailed = true
            return
        }
        FeedbackEngine.shared.selectionChanged()
        withAnimation(.snappy) {
            model.apply(imported)
            pasted = true
        }
        settleLater { pasted = false }
    }

    private func copy() {
        UIPasteboard.general.string = model.report()
        FeedbackEngine.shared.selectionChanged()
        withAnimation(.snappy) { copied = true }
        settleLater { copied = false }
    }

    /// Copied and Pasted show for two seconds, then the buttons read as before.
    private func settleLater(_ settle: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) { settle() }
        }
    }
}

/// Share with a Note: the painter's words on top of the settings text, shared through the
/// system share sheet.
private struct AdvancedShareSheet: View {
    let model: AdvancedSettingsModel
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you notice?", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("advanced-share-note")
                } header: {
                    Text("Note")
                } footer: {
                    Text("What looked right or wrong, and where in the picture.")
                }
                Section {
                    Text(report)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } header: {
                    Text("Included")
                }
            }
            .navigationTitle("Share Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: report, subject: Text("Paint by Moonlight Feedback")) {
                        SwiftUI.Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("advanced-share-send")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .tint(Theme.accent)
    }

    private var report: String { model.report(note: note) }
}
