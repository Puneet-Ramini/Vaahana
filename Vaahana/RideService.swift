//
//  RideService.swift
//  Vaahana
//
//  Handles ride lifecycle transitions and coin operations via Firestore transactions.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Central service for all ride lifecycle mutations.
/// All state changes go through here to ensure atomic coin operations.
final class RideService {
    static let shared = RideService()
    private let db = Firestore.firestore()
    private init() {}

    // MARK: - Accept Ride

    /// Driver accepts a posted ride. Locks the rider's coins atomically.
    func acceptRide(
        _ ride: Ride,
        driverName: String,
        driverPhone: String,
        driverWhatsapp: String
    ) async throws {
        guard let driverId = Auth.auth().currentUser?.uid else {
            throw RideServiceError.notAuthenticated
        }
        let rideRef   = db.collection("rides").document(ride.id.uuidString)
        let riderRef  = db.collection("users").document(ride.riderId)
        let now       = Date()

        try await db.runTransaction { transaction, errorPointer in
            // Verify ride is still posted
            let rideDoc: DocumentSnapshot
            do { rideDoc = try transaction.getDocument(rideRef) }
            catch let e { errorPointer?.pointee = e as NSError; return nil }

            guard let currentStatus = rideDoc.data()?["status"] as? String,
                  currentStatus == "posted" else {
                errorPointer?.pointee = NSError(
                    domain: "RideService", code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "This ride is no longer available."])
                return nil
            }

            // Verify rider has enough coins
            let riderDoc: DocumentSnapshot
            do { riderDoc = try transaction.getDocument(riderRef) }
            catch let e { errorPointer?.pointee = e as NSError; return nil }

            let riderCoins = riderDoc.data()?["coins"] as? Int ?? 0
            guard riderCoins >= ride.coins else {
                errorPointer?.pointee = NSError(
                    domain: "RideService", code: 402,
                    userInfo: [NSLocalizedDescriptionKey: "Rider does not have enough coins."])
                return nil
            }

            // Lock coins from rider's balance
            transaction.updateData([
                "coins":       riderCoins - ride.coins,
                "coinsLocked": FieldValue.increment(Int64(ride.coins))
            ], forDocument: riderRef)

            // Mark ride accepted with driver info
            transaction.updateData([
                "status":         "accepted",
                "driverId":       driverId,
                "driverName":     driverName,
                "driverPhone":    driverPhone,
                "driverWhatsapp": driverWhatsapp,
                "coinStatus":     "locked",
                "coinsLocked":    ride.coins,
                "acceptedAt":     Timestamp(date: now),
                "updatedAt":      Timestamp(date: now)
            ], forDocument: rideRef)

            return nil
        }
    }

    // MARK: - Update Ride Status (enroute / arrived / started)

    /// Advances ride through intermediate states. No coin changes.
    func updateRideStatus(_ ride: Ride, to newStatus: RideStatus) async throws {
        let rideRef = db.collection("rides").document(ride.id.uuidString)
        let now = Timestamp(date: Date())

        var fields: [String: Any] = [
            "status":    newStatus.rawValue,
            "updatedAt": now
        ]
        switch newStatus {
        case .driverEnroute:  fields["driverEnrouteAt"] = now
        case .driverArrived:  fields["arrivedAt"]       = now
        case .rideStarted:    fields["startedAt"]       = now
        default: break
        }
        try await rideRef.updateData(fields)
    }

    // MARK: - Cancel Ride

    /// Cancels the ride. If coins are locked, refunds them to the rider atomically.
    func cancelRide(_ ride: Ride, cancelledBy uid: String, reason: String? = nil) async throws {
        let rideRef  = db.collection("rides").document(ride.id.uuidString)
        let now = Date()

        var cancelFields: [String: Any] = [
            "status":      "cancelled",
            "cancelledBy": uid,
            "cancelledAt": Timestamp(date: now),
            "updatedAt":   Timestamp(date: now)
        ]
        if let reason { cancelFields["cancellationReasonCode"] = reason }

        if ride.coinStatus == .locked && ride.coinsLocked > 0 {
            // Refund coins to rider atomically
            let riderRef = db.collection("users").document(ride.riderId)
            cancelFields["coinStatus"] = "refunded"

            try await db.runTransaction { transaction, errorPointer in
                transaction.updateData([
                    "coins":       FieldValue.increment(Int64(ride.coinsLocked)),
                    "coinsLocked": FieldValue.increment(Int64(-ride.coinsLocked))
                ], forDocument: riderRef)
                transaction.updateData(cancelFields, forDocument: rideRef)
                return nil
            }
        } else {
            try await rideRef.updateData(cancelFields)
        }
    }

    // MARK: - Complete Ride

    /// Completes the ride and transfers coins to the driver.
    /// Uses `finalCoins` (the agreed bid amount) if available, else `coinsLocked`.
    func completeRide(_ ride: Ride) async throws {
        guard let driverId = ride.driverId else {
            throw RideServiceError.missingDriver
        }
        let rideRef   = db.collection("rides").document(ride.id.uuidString)
        let riderRef  = db.collection("users").document(ride.riderId)
        let driverRef = db.collection("users").document(driverId)
        let txnRef    = db.collection("coinTransactions").document(UUID().uuidString)
        let now       = Date()
        let coins     = ride.finalCoins ?? ride.coinsLocked   // prefer agreed bid amount

        try await db.runTransaction { transaction, errorPointer in
            transaction.updateData([
                "coinsLocked": FieldValue.increment(Int64(-coins))
            ], forDocument: riderRef)
            transaction.updateData([
                "coins": FieldValue.increment(Int64(coins))
            ], forDocument: driverRef)
            transaction.updateData([
                "status":           "completed",
                "coinStatus":       "transferred",
                "coinsTransferred": coins,
                "completedAt":      Timestamp(date: now),
                "updatedAt":        Timestamp(date: now)
            ], forDocument: rideRef)
            transaction.setData([
                "rideId":    ride.id.uuidString,
                "fromUid":   ride.riderId,
                "toUid":     driverId,
                "coins":     coins,
                "createdAt": Timestamp(date: now)
            ], forDocument: txnRef)
            return nil
        }
    }

    // MARK: - Place Bid (driver)

    /// Driver places or updates their bid on a posted ride.
    /// One active bid per driver per ride — upserts if one already exists.
    func placeBid(
        ride: Ride,
        existingBidId: String?,
        bidCoins: Int,
        message: String?,
        driverName: String,
        driverPhone: String,
        driverWhatsapp: String
    ) async throws {
        guard let driverId = Auth.auth().currentUser?.uid else {
            throw RideServiceError.notAuthenticated
        }
        let rideRef  = db.collection("rides").document(ride.id.uuidString)
        let bidsRef  = rideRef.collection("bids")
        let now      = Timestamp(date: Date())

        if let existingId = existingBidId {
            // Update the driver's existing bid
            var updates: [String: Any] = [
                "bidCoins":  bidCoins,
                "updatedAt": now
            ]
            if let msg = message { updates["message"] = msg } else { updates["message"] = FieldValue.delete() }
            try await bidsRef.document(existingId).updateData(updates)

            // Keep ride summary fresh
            if bidCoins < (ride.lowestBidCoins ?? Int.max) {
                try await rideRef.updateData(["lowestBidCoins": bidCoins, "latestBidAt": now])
            }
        } else {
            // New bid — create document
            let bidId = UUID().uuidString
            var bidData: [String: Any] = [
                "id":             bidId,
                "rideId":         ride.id.uuidString,
                "driverId":       driverId,
                "driverName":     driverName,
                "driverPhone":    driverPhone,
                "driverWhatsapp": driverWhatsapp,
                "bidCoins":       bidCoins,
                "status":         "active",
                "createdAt":      now,
                "updatedAt":      now
            ]
            if let msg = message { bidData["message"] = msg }
            try await bidsRef.document(bidId).setData(bidData)

            // Update ride bid summary
            let newLowest = min(ride.lowestBidCoins ?? bidCoins, bidCoins)
            try await rideRef.updateData([
                "bidCount":      FieldValue.increment(Int64(1)),
                "lowestBidCoins": newLowest,
                "latestBidAt":   now
            ])
        }
    }

    // MARK: - Withdraw Bid (driver)

    func withdrawBid(ride: Ride, bidId: String) async throws {
        let rideRef = db.collection("rides").document(ride.id.uuidString)
        let bidRef  = rideRef.collection("bids").document(bidId)
        let now     = Timestamp(date: Date())

        try await bidRef.updateData(["status": "withdrawn", "updatedAt": now])
        // Decrement bid count (best-effort)
        try? await rideRef.updateData([
            "bidCount": FieldValue.increment(Int64(-1))
        ])
    }

    // MARK: - Select Bid (rider)

    /// Rider selects a driver bid. Runs a Firestore transaction to atomically:
    /// - mark ride accepted with selected driver details
    /// - lock finalCoins from rider
    /// - mark chosen bid as selected
    /// Then batch-rejects remaining active bids outside the transaction.
    func selectBid(ride: Ride, bid: RideBid) async throws {
        let rideRef   = db.collection("rides").document(ride.id.uuidString)
        let bidRef    = rideRef.collection("bids").document(bid.id)
        let riderRef  = db.collection("users").document(ride.riderId)
        let now       = Date()

        // Transaction: verify + accept + lock coins
        try await db.runTransaction { transaction, errorPointer in
            let rideDoc: DocumentSnapshot
            do { rideDoc = try transaction.getDocument(rideRef) }
            catch let e { errorPointer?.pointee = e as NSError; return nil }

            guard let status = rideDoc.data()?["status"] as? String, status == "posted" else {
                errorPointer?.pointee = NSError(
                    domain: "RideService", code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "This ride is no longer accepting bids."])
                return nil
            }

            let bidDoc: DocumentSnapshot
            do { bidDoc = try transaction.getDocument(bidRef) }
            catch let e { errorPointer?.pointee = e as NSError; return nil }

            guard let bidStatus = bidDoc.data()?["status"] as? String, bidStatus == "active" else {
                errorPointer?.pointee = NSError(
                    domain: "RideService", code: 410,
                    userInfo: [NSLocalizedDescriptionKey: "This bid is no longer available."])
                return nil
            }

            let riderDoc: DocumentSnapshot
            do { riderDoc = try transaction.getDocument(riderRef) }
            catch let e { errorPointer?.pointee = e as NSError; return nil }

            let riderCoins = riderDoc.data()?["coins"] as? Int ?? 0
            guard riderCoins >= bid.bidCoins else {
                errorPointer?.pointee = NSError(
                    domain: "RideService", code: 402,
                    userInfo: [NSLocalizedDescriptionKey: "You don't have enough coins for this bid."])
                return nil
            }

            // Accept ride with selected driver
            transaction.updateData([
                "status":         "accepted",
                "driverId":       bid.driverId,
                "driverName":     bid.driverName,
                "driverPhone":    bid.driverPhone,
                "driverWhatsapp": bid.driverWhatsapp,
                "selectedBidId":  bid.id,
                "finalCoins":     bid.bidCoins,
                "coinStatus":     "locked",
                "coinsLocked":    bid.bidCoins,
                "acceptedAt":     Timestamp(date: now),
                "updatedAt":      Timestamp(date: now)
            ], forDocument: rideRef)

            // Lock coins from rider
            transaction.updateData([
                "coins":       riderCoins - bid.bidCoins,
                "coinsLocked": FieldValue.increment(Int64(bid.bidCoins))
            ], forDocument: riderRef)

            // Mark winning bid as selected
            transaction.updateData([
                "status":    "selected",
                "updatedAt": Timestamp(date: now)
            ], forDocument: bidRef)

            return nil
        }

        // Batch-reject all remaining active bids (outside transaction for scalability)
        if let otherBids = try? await rideRef.collection("bids")
            .whereField("status", isEqualTo: "active")
            .getDocuments() {
            if !otherBids.documents.isEmpty {
                let batch = db.batch()
                for doc in otherBids.documents {
                    batch.updateData(["status": "rejected", "updatedAt": Timestamp(date: now)], forDocument: doc.reference)
                }
                try? await batch.commit()
            }
        }
    }

    // MARK: - Expire Bids (called when ride is cancelled/expired)

    func expireBids(for ride: Ride) async {
        let rideRef = db.collection("rides").document(ride.id.uuidString)
        guard let snapshot = try? await rideRef.collection("bids")
            .whereField("status", isEqualTo: "active")
            .getDocuments() else { return }
        guard !snapshot.documents.isEmpty else { return }
        let batch = db.batch()
        let now = Timestamp(date: Date())
        for doc in snapshot.documents {
            batch.updateData(["status": "expired", "updatedAt": now], forDocument: doc.reference)
        }
        try? await batch.commit()
    }
}



// MARK: - Errors

enum RideServiceError: LocalizedError {
    case notAuthenticated
    case missingDriver

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to perform this action."
        case .missingDriver:    return "No driver assigned to this ride."
        }
    }
}
