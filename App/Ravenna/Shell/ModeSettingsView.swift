#if UNRELEASED
import SwiftUI

/// A mode's Settings in Paint by Mosaic, the frame's answer to the module it is in (`ModeShell`,
/// in `App/Shared`): Paint by Mosaic's own Settings, whose Year row leaves the era through
/// `leaveRavenna`, the same way out `RavennaEra` hands it, so `leave` isn't asked again here.
struct ModeSettingsView: View {
    let year: Int
    let leave: (Int) -> Void

    var body: some View {
        SettingsView()
    }
}
#endif
