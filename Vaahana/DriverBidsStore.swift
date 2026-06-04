//
//  DriverBidsStore.swift
//  Vaahana
//
//  Real-time store for a driver's bids across all rides.
//  Uses a Firestore collection group query on "bids" filtered by driverId.
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

// Enriched bid — bid + the parent ride's route info for display
struct DriverBidEntry: Identifiable {
    var id: String { bid.id }
    var bid: RideBid
    var rideId: String
    var rideFrom: String
    var rideTo: String
}

final class DriverBidsStore: ObservableObject {
    @Published var pendingBids:  [DriverBidEntry] = []   // active (waiting for rider)
    @Published var selectedBids: [DriverBidEntry] = []   // rider chose us
    @Published var closedBids:   [DriverBidEntry] = []   // rejected / withdrawn / expired / autoClosed
    @Published var isLoading = true

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    init() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        startListening(uid: uid)
    }

    deinit { listener?.remove() }

    private func startListening(uid: String) {
        listener = db.collectionGroup("bids")
            .whereField("driverId", isEqualTo: uid)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                let bids = docs.compactMap { doc -> DriverBidEntry? in
                    guard let bid = try? doc.data(as: RideBid.self) else { return nil }
                    let data = doc.data()
                    // Parent ride info is stored alongside bid or we read from the path
                    // Path: rides/{rideId}/bids/{bidId} — extract rideId from parent
                    let rideId = doc.reference.parent.parent?.documentID ?? bid.rideId
                    return DriverBidEntry(
                        bid: bid,
                        rideId: rideId,
                        rideFrom: data["rideFrom"] as? String ?? "",
                        rideTo: data["rideTo"]   as? String ?? ""
                    )
                }
                DispatchQueue.main.async {
                    self.pendingBids  = bids.filter { $0.bid.status == .active }
                    self.selectedBids = bids.filter { $0.bid.status == .selected }
                    self.closedBids   = bids.filter { $0.bid.status.isClosed }
                    self.isLoading    = false
                }
            }
    }

    /// Fetches route details for entries that are missing them (enrichment pass).
    /// Because bids don't store the parent ride's route, we load it on demand.
    func enrichEntries(_ entries: [DriverBidEntry]) async -> [DriverBidEntry] {
        var result: [DriverBidEntry] = []
        for entry in entries {
            if !entry.rideFrom.isEmpty {
                result.append(entry)
                continue
            }
            guard let snap = try? await db.collection("rides").document(entry.rideId).getDocument(),
                  let from = snap.data()?["from"] as? String,
                  let to   = snap.data()?["to"]   as? String else {
                result.append(entry)
                continue
            }
            var enriched = entry
            enriched = DriverBidEntry(bid: entry.bid, rideId: entry.rideId,
                                      rideFrom: from, rideTo: to)
            result.append(enriched)
        }
        return result
    }
}
