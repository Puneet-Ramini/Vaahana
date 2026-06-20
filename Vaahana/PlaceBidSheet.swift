import SwiftUI

struct PlaceBidSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "slash.circle")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("Driver responses are no longer part of Vaahana.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Drivers now claim posted rides directly from the available rides list.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .navigationTitle("Responses removed")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
