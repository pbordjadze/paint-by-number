import SwiftUI

/// Settings › Acknowledgements: the open-source code and published methods behind the
/// template engine, with the license the ported code is used under.
struct AcknowledgementsView: View {
    var body: some View {
        Form {
            Section {
                ForEach(Acknowledgements.code) { AcknowledgementRow(item: $0) }
            } header: {
                Text("Open-Source Code")
            } footer: {
                Text("Swift ports of these libraries are part of the template engine.")
            }

            Section("ISC License") {
                Text(Acknowledgements.iscLicense)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section {
                ForEach(Acknowledgements.methods) { AcknowledgementRow(item: $0) }
            } header: {
                Text("Methods")
            } footer: {
                Text("Published techniques the template engine builds on.")
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AcknowledgementRow: View {
    let item: Acknowledgement

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.name)
                .font(.headline)
            Text(item.usage)
                .font(.subheadline)
            Text(item.credit)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let copyright = item.copyright {
                Text(copyright)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
