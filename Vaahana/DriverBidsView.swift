import SwiftUI

struct DriverBidsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "car.circle")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("Driver bid tracking has been removed.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Drivers now claim rides directly and track them from the active ride flow.")
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
