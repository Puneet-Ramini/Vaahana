import SwiftUI

struct BidListView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("Ride responses are no longer collected in-app.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Drivers now contact riders and claim rides directly from the available rides flow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .navigationTitle("Responses removed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
