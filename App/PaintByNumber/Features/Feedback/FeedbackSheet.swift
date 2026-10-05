import CoreGraphics
import Foundation
import os
import SwiftUI
import UIKit

/// Feedback's review and send sheet: the painting with its marks, a note, a comment per mark
/// (filled in from what its handwriting reads until the painter writes one), what goes along
/// (the painter's own photo only if they turn it on), and Send, which writes the bundle
/// (`FeedbackPackage`) and opens the share sheet, where the painter picks Mail, Messages,
/// AirDrop or Files and who it goes to. Back returns to drawing; sharing it ends feedback.
struct FeedbackSheet: View {
    @Bindable var draft: FeedbackDraft
    /// The bundle was shared.
    var onSent: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.editing

    private enum Phase: Equatable {
        case editing, packing, failed
        case sharing([URL])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FeedbackPictureView(picture: draft.overview, aspectRatio: aspectRatio)
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                        .accessibilityElement()
                        .accessibilityLabel(Text("Your painting with your marks"))
                }
                Section {
                    TextField("What would make this painting better?", text: $draft.note, axis: .vertical)
                        .lineLimit(3...10)
                        .accessibilityIdentifier("feedback-note")
                } header: {
                    Text("Note")
                } footer: {
                    Text("Say what looks wrong or right, and why.")
                }
                if !draft.marks.isEmpty { marks }
                included
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", systemImage: "chevron.backward") { dismiss() }
                        .accessibilityIdentifier("feedback-back")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if phase == .packing {
                        ProgressView()
                    } else {
                        Button("Send", systemImage: "paperplane", action: send)
                            .disabled(draft.isEmpty)
                            .accessibilityIdentifier("feedback-send")
                    }
                }
            }
            .disabled(phase == .packing)
            .overlay(alignment: .bottom) {
                if phase == .packing {
                    Toast(text: String(localized: "Preparing your feedback…"), systemImage: "shippingbox")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .animation(.snappy, value: phase)
        }
        .tint(Theme.accent)
        .interactiveDismissDisabled(phase == .packing)
        .background {
            ActivityShareSheet(items: sharedFiles) { completed in finishSharing(completed: completed) }
        }
        .alert("Couldn’t Prepare Feedback", isPresented: failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again in a moment.")
        }
        .onAppear {
            Log.feedback.notice("Review sheet up")
            draft.prepareReview()
        }
    }

    // MARK: Sections

    private var marks: some View {
        Section {
            ForEach(Array(draft.marks.enumerated()), id: \.element.id) { index, mark in
                MarkRow(
                    number: index + 1, picture: draft.closeUps[mark.id], comment: comment(for: mark.id),
                    isReading: draft.reading.contains(mark.id), reading: draft.readings[mark.id])
            }
        } header: {
            Text("Marks")
        } footer: {
            Text("Each mark gets its own comment. What you wrote on the painting fills it in when it can be read.")
        }
    }

    private var included: some View {
        Section {
            Label("The painting with your marks, and each mark close up", systemImage: "photo")
            Label("Its template, settings and progress", systemImage: "square.grid.3x3")
            LabeledContent {
                Text(verbatim: "\(draft.capture.app), \(draft.capture.device), \(draft.capture.system)")
            } label: {
                Label("App and Device", systemImage: "info.circle")
            }
            if draft.canIncludePhoto {
                Toggle(isOn: $draft.includesPhoto) {
                    Label("Original Photo", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("feedback-photo")
            } else if draft.capture.source?.sampleName != nil {
                Label("Made from a library picture: no photo needed", systemImage: "books.vertical")
            }
        } header: {
            Text("Included")
        } footer: {
            if draft.canIncludePhoto {
                Text("Send opens the share sheet: choose how it goes and who gets it. Your photo helps us remake the painting; it goes only if you turn it on.")
            } else {
                Text("Send opens the share sheet: choose how it goes and who gets it.")
            }
        }
    }

    // MARK: Sending

    private var aspectRatio: CGFloat {
        let canvas = draft.capture.canvasRect
        return canvas.height > 0 ? canvas.width / canvas.height : 1
    }

    private func comment(for mark: Date) -> Binding<String> {
        Binding { draft.comments[mark] ?? "" } set: { draft.comments[mark] = $0 }
    }

    private var failed: Binding<Bool> {
        Binding { phase == .failed } set: { if !$0 { phase = .editing } }
    }

    private var sharedFiles: [URL] {
        if case .sharing(let files) = phase { files } else { [] }
    }

    private func send() {
        phase = .packing
        Task {
            do {
                phase = .sharing(try await draft.package())
            } catch {
                Log.feedback.error("Packing feedback failed: \(String(describing: error), privacy: .public)")
                phase = .failed
            }
        }
    }

    /// The share sheet closed: the receivers have their copies, so the files go either way;
    /// shared, feedback is done.
    private func finishSharing(completed: Bool) {
        let files = sharedFiles
        phase = .editing
        if let first = files.first {
            Task { await Background.run { ArtworkExporter.removeExport(at: first) } }
        }
        if completed { onSent() }
    }
}

/// A mark in the review sheet: its close-up, its number and its comment.
private struct MarkRow: View {
    let number: Int
    let picture: FeedbackPicture?
    @Binding var comment: String
    let isReading: Bool
    let reading: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FeedbackPictureView(picture: picture, aspectRatio: 1)
                .frame(width: 72, height: 72)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                TextField("What should we look at here?", text: $comment, axis: .vertical)
                    .lineLimit(1...6)
                    .accessibilityLabel(Text(title))
                    .accessibilityIdentifier("feedback-mark-\(number)")
                if isReading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Reading your handwriting…")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let reading, reading == comment {
                    Label("Read from your handwriting", systemImage: "text.viewfinder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        String(localized: "feedback.mark.title", defaultValue: "Mark \(number)",
               comment: "Feedback's review sheet: the name of one of the marks drawn on the painting; the argument is its number")
    }
}

/// A painting picture with the ink over it, fitted; a spinner until it's drawn.
struct FeedbackPictureView: View {
    let picture: FeedbackPicture?
    let aspectRatio: CGFloat

    var body: some View {
        ZStack {
            if let picture {
                Image(decorative: picture.painting, scale: 1)
                    .resizable()
                    .scaledToFit()
                if let ink = picture.ink {
                    Image(decorative: ink, scale: 1)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Color.secondary.opacity(0.12)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .overlay { ProgressView() }
            }
        }
    }
}
