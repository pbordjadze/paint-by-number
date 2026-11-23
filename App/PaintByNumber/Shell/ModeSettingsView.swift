#if UNRELEASED
import Ravenna
import SwiftUI

/// A mode's Settings in Paint by Moonlight, the frame's answer to the module it is in
/// (`ModeShell`, in `App/Shared`): About's Year, whose wheel leaves the mode.
struct ModeSettingsView: View {
    let year: Int
    let leave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsClock = false
    /// The year the Year row's wheel rests on (`EraClock.Reading`).
    @State private var clockYear = EraClock.Reading()

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    Button {
                        withAnimation { showsClock.toggle() }
                        // Closed without opening an era: the row reads its own year again.
                        clockYear.isOpen = showsClock
                        if !showsClock { clockYear.year = nil }
                    } label: {
                        LabeledContent {
                            EraClock.Value(clockYear, home: year).foregroundStyle(.tint)
                        } label: {
                            SwiftUI.Label {
                                Text("Year").foregroundStyle(Color.primary)
                            } icon: {
                                Image(systemName: "clock")
                            }
                        }
                    }
                    .accessibilityIdentifier("about-year")
                    if showsClock {
                        EraClock(year: year) { chosen in
                            guard chosen != year, EraYear.opensAnEra(chosen) else { return }
                            dismiss()
                            leave(chosen)
                        }
                        .reporting(to: clockYear)
                        .accessibilityIdentifier("era-clock")
                    }
                }
            }
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif
