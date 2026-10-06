import Foundation
import PaintCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.autoAdvance) private var autoAdvance = true
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.sounds) private var sounds = true
    @AppStorage(SettingsKey.paintingLength) private var paintingLength = PaintingLength.default
    @AppStorage(SettingsKey.paperSize) private var paper: PDFExporter.Paper = .default(for: Locale.current.region)
    @AppStorage(SettingsKey.paperAppearance) private var paperAppearance = PaperAppearance.default
    @AppStorage(SettingsKey.lineWeight) private var lineWeight = LineWeight.default
    @AppStorage(SettingsKey.colorNames) private var colorNames: ColorNameStyle = .default
    @AppStorage(SettingsKey.paletteRows) private var paletteRows = PaletteRows.default
    @AppStorage(SettingsKey.paletteOrder) private var paletteOrder = PaletteOrder.default
    @State private var path: [Destination] = []

    private let appInfo = AppInfo()

    private enum Destination: Hashable { case acknowledgements }
    @State private var tipsReset = false

    init() {
        #if DEBUG
        if ShellDemo.current == .settingsAcknowledgements { _path = State(initialValue: [.acknowledgements]) }
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    Toggle(isOn: $autoAdvance) {
                        SwiftUI.Label("Advance to Next Color", systemImage: "arrow.forward.circle")
                    }
                    // The nicknames are English: in other languages the plain names are all there is.
                    if ColorNameText.nicknamesAvailable() {
                        Picker(selection: $colorNames) {
                            Text("Playful").tag(ColorNameStyle.playful)
                            Text("Plain").tag(ColorNameStyle.plain)
                        } label: {
                            SwiftUI.Label("Color Names", systemImage: "textformat")
                        }
                        .accessibilityIdentifier("settings-color-names")
                    }
                } header: {
                    // Not the "Painting" key: that one names a picture, this one the activity.
                    Text(String(localized: "settings.section.painting", defaultValue: "Painting",
                                comment: "Header of the Settings section about how painting behaves (the activity, not a picture); it holds Advance to Next Color"))
                } footer: {
                    Text("When you finish a color, the next one is picked up automatically.")
                }

                Section {
                    Picker(selection: $paletteRows) {
                        ForEach(PaletteRows.allCases) { rows in
                            Text(rows.name).tag(rows)
                        }
                    } label: {
                        SwiftUI.Label("Rows", systemImage: "square.grid.3x2")
                    }
                    .accessibilityIdentifier("settings-palette-rows")
                    Picker(selection: $paletteOrder) {
                        ForEach(PaletteOrder.allCases) { order in
                            Text(order.name).tag(order)
                        }
                    } label: {
                        SwiftUI.Label("Order", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("settings-palette-order")
                } header: {
                    Text(String(localized: "settings.section.palette", defaultValue: "Palette",
                                comment: "Header of the Settings section on how the painting screen's palette of swatches is laid out"))
                } footer: {
                    Text("Change these while painting from More › Palette, where Arrange Colors puts a painting’s colors in your own order.")
                }

                Section {
                    Picker(selection: $paperAppearance) {
                        ForEach(PaperAppearance.allCases) { appearance in
                            Text(appearance.name).tag(appearance)
                        }
                    } label: {
                        SwiftUI.Label("Paper", systemImage: "circle.lefthalf.filled")
                    }
                    .accessibilityIdentifier("paper-appearance")
                    Picker(selection: $lineWeight) {
                        ForEach(LineWeight.allCases) { weight in
                            Text(weight.name).tag(weight)
                        }
                    } label: {
                        SwiftUI.Label("Line Weight", systemImage: "lineweight")
                    }
                    .accessibilityIdentifier("settings-line-weight")
                } footer: {
                    Text("Dark paper is easier on the eyes in a dark room. Line Weight sets how heavy a painting’s drawn lines are, on screen and on paper.")
                }

                Section {
                    Button {
                        PaintTips.showAgain()
                        tipsReset = true
                    } label: {
                        if tipsReset {
                            SwiftUI.Label("Tips Will Show Again", systemImage: "checkmark")
                        } else {
                            SwiftUI.Label("Show Tips Again", systemImage: "lightbulb")
                        }
                    }
                    .disabled(tipsReset)
                } footer: {
                    Text("Short tips explain painting gestures as you go.")
                }

                Section("Feedback") {
                    Toggle(isOn: $haptics) {
                        SwiftUI.Label("Haptics", systemImage: "hand.tap")
                    }
                    Toggle(isOn: $sounds) {
                        SwiftUI.Label("Sounds", systemImage: "speaker.wave.2")
                    }
                }

                Section {
                    Picker(selection: $paintingLength) {
                        ForEach(PaintingLength.allCases, id: \.self) { length in
                            Text(length.name).tag(length)
                        }
                    } label: {
                        SwiftUI.Label("Painting Length", systemImage: "hourglass")
                    }
                    .accessibilityIdentifier("painting-length")
                } header: {
                    Text("New Paintings")
                } footer: {
                    Text(paintingLength.footer)
                        .accessibilityIdentifier("painting-length-footer")
                }

                Section {
                    Picker(selection: $paper) {
                        ForEach(PDFExporter.Paper.allCases) { paper in
                            Text(paper.name).tag(paper)
                        }
                    } label: {
                        SwiftUI.Label("Printed Templates", systemImage: "printer")
                    }
                } footer: {
                    Text("The paper size printed templates are laid out for.")
                }

                Section {
                    LabeledContent {
                        Text(appInfo.summary)
                    } label: {
                        SwiftUI.Label("Version", systemImage: "info.circle")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("about-version")
                    NavigationLink(value: Destination.acknowledgements) {
                        SwiftUI.Label("Acknowledgements", systemImage: "text.book.closed")
                    }
                    .accessibilityIdentifier("about-acknowledgements")
                } header: {
                    Text("About")
                } footer: {
                    Text("Your photos and paintings stay on this device unless you share them. Paint by Moonlight collects no data.")
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .acknowledgements: AcknowledgementsView()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .tint(Theme.accent)
    }
}
