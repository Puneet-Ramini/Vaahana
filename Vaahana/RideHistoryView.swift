//
//  RideHistoryView.swift
//  Vaahana
//
//  Shows past (completed / cancelled / expired) rides for either role.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct RideHistoryView: View {
    let role: UserRole

    @State private var pastRides: [Ride] = []
    @State private var isLoading = true

    private let db = Firestore.firestore()
    private var uid: String { Auth.auth().currentUser?.uid ?? "" }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pastRides.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                    Text("No past rides yet")
                        .font(.headline)
                    Text("Completed and cancelled rides will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(pastRides) { ride in
                    historyRow(ride)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Ride History")
        .navigationBarTitleDisplayMode(.large)
        .task { await loadHistory() }
    }

    // MARK: - Row

    private func historyRow(_ ride: Ride) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(ride.from) → \(ride.to)")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                StatusChip(status: ride.status)
            }
            HStack(spacing: 12) {
                Label(ride.pickupDateShort, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Posted \(ride.postedAtShort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let name = ride.driverName, role == .rider {
                Text("Driver: \(name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if role == .driver {
                Text("Rider: \(ride.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Load

    private func loadHistory() async {
        // "riderId" for riders, "driverId" for drivers
        let fieldKey = role == .rider ? "riderId" : "driverId"
        let query = db.collection("rides")
            .whereField(fieldKey, isEqualTo: uid)
            .whereField("status", in: ["completed", "cancelled", "expired"])

        if let snapshot = try? await query.getDocuments() {
            let rides = snapshot.documents.compactMap { try? $0.data(as: Ride.self) }
            pastRides = rides.sorted { $0.createdAt > $1.createdAt }
        }
        isLoading = false
    }
}
