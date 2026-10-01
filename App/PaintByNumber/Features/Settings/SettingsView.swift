import Foundation
import PaintCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.autoAdvance) private var autoAdvance = true
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.sounds) private var sounds = true
    @AppStorage(SettingsKey.defaultColorCount) private var defaultColorCount = Preferences.defaultColorCountValue
    @AppStorage(SettingsKey.paperSize) private var paper: PDFExporter.Paper = .default(for: Locale.current.region)
    @AppStorage(SettingsKey.colorNames) private var colorNames: ColorNameStyle = .playful
    #if DEBUG
    @State private var path: [Destination] = ShellDemo.current == .settingsAcknowledgements ? [.acknowledgements] : []
    #else
    @State private var path: [Destination] = []
    #endif

    private let appInfo = AppInfo()

    private enum Destination: Hashable { case acknowledgements }
    @State private var tipsReset = false

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
                    // Fine steps where each color matters, coarse ones for large palettes.
                    Stepper {
                        defaultColorCount = min(
                            defaultColorCount + (defaultColorCount < 40 ? 2 : 10), GenerationSettings.colorCountRange.upperBound)
                    } onDecrement: {
                        defaultColorCount = max(
                            defaultColorCount - (defaultColorCount <= 40 ? 2 : 10), GenerationSettings.colorCountRange.lowerBound)
                    } label: {
                        SwiftUI.Label {
                            HStack {
                                Text("Starting Colors")
                                Spacer()
                                Text(defaultColorCount, format: .number)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "paintpalette")
                        }
                    }
                    Picker(selection: $paper) {
                        ForEach(PDFExporter.Paper.allCases) { paper in
                            Text(paper.name).tag(paper)
                        }
                    } label: {
                        SwiftUI.Label("Printed Templates", systemImage: "printer")
                    }
                } header: {
                    Text("New Paintings")
                } footer: {
                    Text("The number of colors new paintings start with, and the paper size for printed templates.")
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
                    Text("Your photos and paintings stay on this device unless you share them. Paint by Numbers collects no data.")
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
