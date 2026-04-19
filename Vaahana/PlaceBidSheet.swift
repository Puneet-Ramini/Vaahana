//
//  PlaceBidSheet.swift
//  Vaahana
//
//  Driver sheet to place or update a bid on a posted ride.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct PlaceBidSheet: View {
    let ride: Ride
    let existingBid: RideBid?

    @Environment(\.dismiss) private var dismiss
    @State private var message: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let db = Firestore.firestore()
    private var uid: String { Auth.auth().currentUser?.uid ?? "" }

    init(ride: Ride, existingBid: RideBid? = nil) {
        self.ride = ride
        self.existingBid = existingBid
        _message      = State(initialValue: existingBid?.message ?? "")
    }

    private var isEditing: Bool { existingBid != nil }
    private var isValid: Bool   { !isSubmitting }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Ride summary
                Section("Ride") {
                    HStack {
                        Text(ride.from).fontWeight(.semibold)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(ride.to).fontWeight(.semibold)
                    }
                }

                Section {
                    Text("Send a short note so the rider knows your ETA or any pickup details.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("You can edit or withdraw your response until the rider chooses you.")
                }

                // Optional message
                Section("Message (optional)") {
                    TextField("e.g. Can be there in 10 mins", text: $message, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Bid" : "Place Bid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    // Withdraw button when editing
                    if isEditing {
                        Button(role: .destructive) {
                            withdraw()
                        } label: {
                            Text("Withdraw Bid")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                    }

                    // Submit / Update
                    Button { submit() } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text(isEditing ? "Update Bid" : "Place Bid")
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isValid ? Color.black : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(!isValid)
                }
                .padding()
                .background(Color(UIColor.systemGroupedBackground))
            }
        }
    }

    // MARK: - Actions

    private func submit() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                let profile = try? await db.collection("users").document(uid).getDocument().data()
                let driverName     = Auth.auth().currentUser?.displayName
                                     ?? (profile?["displayName"] as? String ?? "Driver")
                let driverPhone    = profile?["phone"] as? String ?? ""
                let driverWhatsapp = profile?["whatsapp"] as? String ?? driverPhone

                try await RideService.shared.placeBid(
                    ride:          ride,
                    existingBidId: existingBid?.id,
                    message:       message.isEmpty ? nil : message,
                    driverName:    driverName,
                    driverPhone:   driverPhone,
                    driverWhatsapp: driverWhatsapp
                )
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }

    private func withdraw() {
        guard let bid = existingBid else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await RideService.shared.withdrawBid(ride: ride, bidId: bid.id)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}
