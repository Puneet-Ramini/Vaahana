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

    /// Completes the ride and transfers locked coins to the driver atomically.
    /// Also writes an immutable audit record to `coinTransactions`.
    func completeRide(_ ride: Ride) async throws {
        guard let driverId = ride.driverId else {
            throw RideServiceError.missingDriver
        }
        let rideRef   = db.collection("rides").document(ride.id.uuidString)
        let riderRef  = db.collection("users").document(ride.riderId)
        let driverRef = db.collection("users").document(driverId)
        let txnRef    = db.collection("coinTransactions").document(UUID().uuidString)
        let now       = Date()
        let coins     = ride.coinsLocked

        try await db.runTransaction { transaction, errorPointer in
            // Unlock coins from rider pool
            transaction.updateData([
                "coinsLocked": FieldValue.increment(Int64(-coins))
            ], forDocument: riderRef)

            // Credit driver
            transaction.updateData([
                "coins": FieldValue.increment(Int64(coins))
            ], forDocument: driverRef)

            // Mark ride completed
            transaction.updateData([
                "status":           "completed",
                "coinStatus":       "transferred",
                "coinsTransferred": coins,
                "completedAt":      Timestamp(date: now),
                "updatedAt":        Timestamp(date: now)
            ], forDocument: rideRef)

            // Immutable audit log
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
