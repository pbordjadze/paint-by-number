import Foundation
import PaintCore
import SwiftUI

struct SettingsView: View {
    /// Settings › Advanced opens over the whole window (in regular widths, where this sheet is a
    /// small card) instead of inside the sheet.
    let advancedFullScreen: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(Library.self) private var library
    @AppStorage(SettingsKey.autoAdvance) private var autoAdvance = true
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.sounds) private var sounds = true
    @AppStorage(SettingsKey.paintingLength) private var paintingLength = PaintingLength.default
    @AppStorage(SettingsKey.paperSize) private var paper: PDFExporter.Paper = .default(for: Locale.current.region)
    @AppStorage(SettingsKey.paperAppearance) private var paperAppearance = PaperAppearance.default
    @AppStorage(SettingsKey.colorNames) private var colorNames: ColorNameStyle = .playful
    @AppStorage(SettingsKey.paletteRows) private var paletteRows = PaletteRows.default
    @AppStorage(SettingsKey.paletteOrder) private var paletteOrder = PaletteOrder.default
    @State private var path: [Destination] = []
    @State private var isShowingAdvanced = false

    private let appInfo = AppInfo()

    private enum Destination: Hashable { case acknowledgements, advanced }
    @State private var tipsReset = false

    init(advancedFullScreen: Bool = false) {
        self.advancedFullScreen = advancedFullScreen
        #if DEBUG
        switch ShellDemo.current {
        case .settingsAcknowledgements?: _path = State(initialValue: [.acknowledgements])
        case let demo? where demo.opensAdvanced && !advancedFullScreen: _path = State(initialValue: [.advanced])
        default: break
        }
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
                } footer: {
                    Text("Dark paper is easier on the eyes in a dark room.")
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
                    if advancedFullScreen {
                        Button { isShowingAdvanced = true } label: { advancedRow }
                            .accessibilityIdentifier("settings-advanced")
                    } else {
                        NavigationLink(value: Destination.advanced) { advancedRow }
                            .accessibilityIdentifier("settings-advanced")
                    }
                } footer: {
                    Text("Line art, line appearance and the template pipeline, with a live preview. For testers: these settings may change between versions.")
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
                case .advanced: AdvancedSettingsView(library: library, picture: advancedPicture)
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
        .fullScreenCover(isPresented: $isShowingAdvanced) {
            NavigationStack {
                AdvancedSettingsView(library: library, picture: advancedPicture) { isShowingAdvanced = false }
            }
            .tint(Theme.accent)
        }
        #if DEBUG
        .task {
            guard advancedFullScreen, ShellDemo.current?.opensAdvanced == true else { return }
            // Once the settings sheet is up: a cover can't be presented while it is still arriving.
            try? await Task.sleep(for: .milliseconds(600))
            isShowingAdvanced = true
        }
        #endif
    }

    /// Advanced, marked Experimental, in the look of a row that opens a screen.
    private var advancedRow: some View {
        HStack(spacing: 8) {
            SwiftUI.Label {
                Text("Advanced")
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "slider.horizontal.3")
            }
            Spacer(minLength: 8)
            Text("Experimental")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.accent.opacity(0.14), in: .capsule)
            if advancedFullScreen {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
    }

    /// The picture a demo scenario previews; nil leaves the choice to the screen.
    private var advancedPicture: AdvancedSettingsModel.Picture? {
        #if DEBUG
        return ShellDemo.current?.advancedPicture.map { .sample($0) }
        #else
        return nil
        #endif
    }
}
