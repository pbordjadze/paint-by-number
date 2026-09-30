import PaintCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.autoAdvance) private var autoAdvance = true
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.sounds) private var sounds = true
    @AppStorage(SettingsKey.defaultColorCount) private var defaultColorCount = Preferences.defaultColorCountValue
    @AppStorage(SettingsKey.paperSize) private var paper: PDFExporter.Paper = .default(for: Locale.current.region)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $autoAdvance) {
                        SwiftUI.Label("Advance to Next Color", systemImage: "arrow.forward.circle")
                    }
                } header: {
                    Text("Painting")
                } footer: {
                    Text("When you finish a color, the next one is picked up automatically.")
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
                    Text("Photos are turned into templates entirely on this device and never leave it.")
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
