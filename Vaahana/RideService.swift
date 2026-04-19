//
//  RideService.swift
//  Vaahana
//
//  Handles ride lifecycle transitions and bid selection via Firestore transactions.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Central service for all ride lifecycle mutations.
/// All state changes go through here to ensure atomic ride assignment updates.
final class RideService {
    static let shared = RideService()
    private let db = Firestore.firestore()
    private init() {}

    // MARK: - Accept Ride

    /// Driver accepts a posted ride.
    func acceptRide(
        _ ride: Ride,
        driverName: String,
        driverPhone: String,
        driverWhatsapp: String
    ) async throws {
        guard let driverId = Auth.auth().currentUser?.uid else {
            throw RideServiceError.notAuthenticated
        }
        let rideRef = db.collection("rides").document(ride.id.uuidString)
        let now     = Date()

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

            // Mark ride accepted with driver info
            transaction.updateData([
                "status":         "accepted",
                "driverId":       driverId,
                "driverName":     driverName,
                "driverPhone":    driverPhone,
                "driverWhatsapp": driverWhatsapp,
                "acceptedAt":     Timestamp(date: now),
                "updatedAt":      Timestamp(date: now)
            ], forDocument: rideRef)

            return nil
        }
    }

    // MARK: - Update Ride Status (enroute / arrived / started)

    /// Advances ride through driver-controlled intermediate states.
    /// Validates: actor is assigned driver, current status is not final, transition is legal.
    func updateRideStatus(_ ride: Ride, to newStatus: RideStatus) async throws {
        guard let actorId = Auth.auth().currentUser?.uid else {
            throw RideServiceError.notAuthenticated
        }

        // Legal driver-only forward transitions
        let validTransitions: [String: String] = [
            "accepted":       "driver_enroute",
            "driver_enroute": "driver_arrived",
            "driver_arrived": "ride_started"
        ]

        let rideRef = db.collection("rides").document(ride.id.uuidString)
        let now = Timestamp(date: Date())

        try await db.runTransaction { transaction, errorPointer in
            let rideDoc: DocumentSnapshot
            do { rideDoc = try transaction.getDocument(rideRef) }
            catch let e { errorPointer?.pointee = e as NSError; return nil }

            guard let data = rideDoc.data() else {
                errorPointer?.pointee = NSError(domain: "RideService", code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Ride not found."])
                return nil
            }

            let rawStatus = data["status"] as? String ?? ""

            // Final-state immutability guard
            if RideStatus(rawValue: rawStatus)?.isFinal == true {
                errorPointer?.pointee = NSError(domain: "RideService", code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "This ride is already finished and cannot be modified."])
                return nil
            }

            // Actor must be the assigned driver
            guard data["driverId"] as? String == actorId else {
                errorPointer?.pointee = NSError(domain: "RideService", code: 403,
                    userInfo: [NSLocalizedDescriptionKey: "Only the assigned driver can advance this ride."])
                return nil
            }

            // Validate legal transition
            guard validTransitions[rawStatus] == newStatus.rawValue else {
                errorPointer?.pointee = NSError(domain: "RideService", code: 422,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid status transition: \(rawStatus) → \(newStatus.rawValue)."])
                return nil
            }

            var fields: [String: Any] = ["status": newStatus.rawValue, "updatedAt": now]
            switch newStatus {
            case .driverEnroute: fields["driverEnrouteAt"] = now
            case .driverArrived: fields["arrivedAt"]       = now
            case .rideStarted:   fields["startedAt"]       = now
            default: break
            }
            transaction.updateData(fields, forDocument: rideRef)
            return nil
        }
    }

    // MARK: - Cancel Ride

    /// Cancels the ride. Validates ownership, final-state, and cancellation rules.
    /// Clears driver's activeRideId atomically when needed.
    func cancelRide(_ ride: Ride, cancelledBy uid: String, reason: String? = nil) async throws {
        guard let actorId = Auth.auth().currentUser?.uid, actorId == uid else {
            throw RideServiceError.notAuthenticated
        }

        // Ownership: actor must be the rider or the assigned driver
        let isRider  = uid == ride.riderId
        let isDriver = ride.driverId != nil && uid == ride.driverId
        guard isRider || isDriver else {
            throw RideServiceError.notAuthorized
        }

        let rideRef   = db.collection("rides").document(ride.id.uuidString)
        let driverRef = ride.driverId.map { db.collection("users").document($0) }
        let now       = Date()

        var cancelFields: [String: Any] = [
            "status":      "cancelled",
            "cancelledBy": uid,
            "cancelledAt": Timestamp(date: now),
            "updatedAt":   Timestamp(date: now)
        ]
        if let reason { cancelFields["cancellationReasonCode"] = reason }

        try await db.runTransaction { transaction, errorPointer in
            let rideDoc: DocumentSnapshot
            do { rideDoc = try transaction.getDocument(rideRef) }
            catch let e { errorPointer?.pointee = e as NSError; return nil }

            let rawStatus = rideDoc.data()?["status"] as? String ?? ""
            let currentStatus = RideStatus(rawValue: rawStatus) ?? .posted

            // Final-state immutability guard
            if currentStatus.isFinal {
                errorPointer?.pointee = NSError(domain: "RideService", code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "This ride is already in a final state."])
                return nil
            }

            // Rider cannot cancel once the ride is in progress
            if isRider && rawStatus == RideStatus.rideStarted.rawValue {
                errorPointer?.pointee = NSError(domain: "RideService", code: 403,
                    userInfo: [NSLocalizedDescriptionKey: "A ride in progress can only be cancelled by the driver."])
                return nil
            }

            // Clear driver's active ride slot
            if let dr = driverRef {
                transaction.updateData(["activeRideId": FieldValue.delete()], forDocument: dr)
            }

            transaction.updateData(cancelFields, forDocument: rideRef)
            return nil
        }
    }

    // MARK: - Complete Ride

    /// Completes the ride.
    /// Validates: actor is assigned driver, ride is in rideStarted state.
    func completeRide(_ ride: Ride) async throws {
        guard let actorId = Auth.auth().currentUser?.uid else {
            throw RideServiceError.notAuthenticated
        }
        guard let driverId = ride.driverId else {
            throw RideServiceError.missingDriver
        }
        guard actorId == driverId else {
            throw RideServiceError.notAuthorized
        }

        let rideRef   = db.collection("rides").document(ride.id.uuidString)
        let driverRef = db.collection("users").document(driverId)
        let now       = Date()

        try await db.runTransaction { transaction, errorPointer in
            let rideDoc: DocumentSnapshot
            do { rideDoc = try transaction.getDocument(rideRef) }
            catch let e { errorPointer?.pointee = e as NSError; return nil }

            let rawStatus = rideDoc.data()?["status"] as? String ?? ""

            // Final-state immutability guard
            if RideStatus(rawValue: rawStatus)?.isFinal == true {
                errorPointer?.pointee = NSError(domain: "RideService", code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "This ride is already in a final state."])
                return nil
            }

            // Must be in rideStarted to complete
            guard rawStatus == RideStatus.rideStarted.rawValue else {
                errorPointer?.pointee = NSError(domain: "RideService", code: 422,
                    userInfo: [NSLocalizedDescriptionKey: "Ride must be started before it can be completed."])
                return nil
            }

            transaction.updateData([
                "activeRideId": FieldValue.delete()
            ], forDocument: driverRef)
            transaction.updateData([
                "status":      "completed",
                "completedAt": Timestamp(date: now),
                "updatedAt":   Timestamp(date: now)
            ], forDocument: rideRef)
            return nil
        }
    }

    // MARK: - Place Bid (driver)

    /// Driver places or updates their bid on a posted ride.
    /// One active bid per driver per ride — upserts if one already exists.
    /// Rejects if driver is offline (isAvailable == false) or already on an active ride (activeRideId set).
    func placeBid(
        ride: Ride,
        existingBidId: String?,
        message: String?,
        driverName: String,
        driverPhone: String,
        driverWhatsapp: String
    ) async throws {
        guard let driverId = Auth.auth().currentUser?.uid else {
            throw RideServiceError.notAuthenticated
        }

        // Guard: driver must be online and not on an active ride
        let driverSnap = try await db.collection("users").document(driverId).getDocument()
        let driverData = driverSnap.data() ?? [:]
        let isAvailable  = driverData["isAvailable"] as? Bool ?? true
        let activeRideId = driverData["activeRideId"] as? String

        if !isAvailable {
            throw RideServiceError.driverOffline
        }
        if let arId = activeRideId, !arId.isEmpty {
            throw RideServiceError.driverBusy
        }

        let rideRef  = db.collection("rides").document(ride.id.uuidString)
        let bidsRef  = rideRef.collection("bids")
        let now      = Timestamp(date: Date())

        // Verify ride is still accepting bids
        let rideSnap = try await rideRef.getDocument()
        guard rideSnap.data()?["status"] as? String == "posted" else {
            throw RideServiceError.rideNotAvailable
        }

        if let existingId = existingBidId {
            // Update the driver's existing bid
            var updates: [String: Any] = [
                "updatedAt": now
            ]
            if let msg = message { updates["message"] = msg } else { updates["message"] = FieldValue.delete() }
            try await bidsRef.document(existingId).updateData(updates)
            try await rideRef.updateData(["latestBidAt": now])
        } else {
            // New bid — create document, embed route info for collection-group queries
            let bidId = UUID().uuidString
            var bidData: [String: Any] = [
                "id":             bidId,
                "rideId":         ride.id.uuidString,
                "driverId":       driverId,
                "driverName":     driverName,
                "driverPhone":    driverPhone,
                "driverWhatsapp": driverWhatsapp,
                "status":         "active",
                "createdAt":      now,
                "updatedAt":      now,
                // Denormalized route info for DriverBidsStore collection-group listener
                "rideFrom":       ride.from,
                "rideTo":         ride.to
            ]
            if let msg = message { bidData["message"] = msg }
            try await bidsRef.document(bidId).setData(bidData)

            // Update ride bid summary
            try await rideRef.updateData([
                "bidCount":      FieldValue.increment(Int64(1)),
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
    /// - verify caller is the ride's rider
    /// - verify chosen driver has no active ride
    /// - mark ride accepted with selected driver details
    /// - mark chosen bid as selected
    /// Then batch-rejects remaining bids on this ride and auto-closes the selected
    /// driver's other active bids across all rides.
    func selectBid(ride: Ride, bid: RideBid) async throws {
        guard let actorId = Auth.auth().currentUser?.uid, actorId == ride.riderId else {
            throw RideServiceError.notAuthorized
        }
        let rideRef   = db.collection("rides").document(ride.id.uuidString)
        let bidRef    = rideRef.collection("bids").document(bid.id)
        let driverRef = db.collection("users").document(bid.driverId)
        let now       = Date()

        // Transaction: verify + accept
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

            // Verify the chosen driver is not already on an active ride
            let driverDoc: DocumentSnapshot
            do { driverDoc = try transaction.getDocument(driverRef) }
            catch let e { errorPointer?.pointee = e as NSError; return nil }

            if let arId = driverDoc.data()?["activeRideId"] as? String, !arId.isEmpty {
                errorPointer?.pointee = NSError(
                    domain: "RideService", code: 423,
                    userInfo: [NSLocalizedDescriptionKey: "This driver just accepted another ride. Please choose a different driver."])
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
                "acceptedAt":     Timestamp(date: now),
                "updatedAt":      Timestamp(date: now)
            ], forDocument: rideRef)

            // Mark the driver's activeRideId so they can't be double-booked
            transaction.updateData([
                "activeRideId": ride.id.uuidString
            ], forDocument: driverRef)

            // Mark winning bid as selected
            transaction.updateData([
                "status":    "selected",
                "updatedAt": Timestamp(date: now)
            ], forDocument: bidRef)

            return nil
        }

        // Batch-reject all remaining active bids on this ride (outside transaction)
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

        // Auto-close all other active bids by this driver across all rides
        if let driverOtherBids = try? await db.collectionGroup("bids")
            .whereField("driverId", isEqualTo: bid.driverId)
            .whereField("status", isEqualTo: "active")
            .getDocuments() {
            if !driverOtherBids.documents.isEmpty {
                let batch = db.batch()
                for doc in driverOtherBids.documents {
                    batch.updateData(["status": "autoClosed", "updatedAt": Timestamp(date: now)], forDocument: doc.reference)
                }
                try? await batch.commit()
            }
        }
    }

    // MARK: - Expire Stale Ride (client-side, called by rider listener)

    /// Marks a posted ride as expired when its hot window has passed.
    /// Only called for rides owned by the current user — no ownership check needed.
    func expireRide(_ ride: Ride) async {
        guard ride.status == .posted, !ride.isHot else { return }
        let rideRef = db.collection("rides").document(ride.id.uuidString)
        let now = Timestamp(date: Date())
        try? await rideRef.updateData(["status": "expired", "updatedAt": now])
        await expireBids(for: ride)
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
    case notAuthorized
    case missingDriver
    case driverOffline
    case driverBusy
    case rideNotAvailable
    case cancelNotAllowed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:  return "You must be signed in to perform this action."
        case .notAuthorized:     return "You are not authorized to perform this action."
        case .missingDriver:     return "No driver assigned to this ride."
        case .driverOffline:     return "You must be online to place a bid. Turn on your availability toggle."
        case .driverBusy:        return "You already have an active ride. Complete or cancel it before placing new bids."
        case .rideNotAvailable:  return "This ride is no longer accepting bids."
        case .cancelNotAllowed:  return "This ride cannot be cancelled at its current stage."
        }
    }
}
