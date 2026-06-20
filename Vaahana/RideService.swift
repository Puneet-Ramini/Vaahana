//
//  RideService.swift
//  Vaahana
//
//  Handles the managed ride lifecycle.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

/// Central service for all ride lifecycle mutations.
/// All state changes go through here to ensure atomic ride assignment updates.
final class RideService {
    static let shared = RideService()
    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private init() {}

    func createRide(
        name: String,
        phone: String,
        phoneCountryCode: String,
        whatsappPhone: String,
        whatsappCountryCode: String,
        from: String,
        to: String,
        miles: Double,
        pickupLat: Double?,
        pickupLng: Double?,
        hotDuration: Int,
        pickupDate: Date,
        notes: String?
    ) async throws {
        _ = try await functions.httpsCallable("createRideRequest").call([
            "name": name,
            "phone": phone,
            "phoneCountryCode": phoneCountryCode,
            "whatsappPhone": whatsappPhone,
            "whatsappCountryCode": whatsappCountryCode,
            "from": from,
            "to": to,
            "miles": miles,
            "pickupLat": pickupLat as Any,
            "pickupLng": pickupLng as Any,
            "hotDuration": hotDuration,
            "pickupDate": ISO8601DateFormatter().string(from: pickupDate),
            "notes": notes as Any,
            "source": "app",
        ])
    }

    // MARK: - Accept Ride

    /// Driver accepts a posted ride.
    func acceptRide(
        _ ride: Ride,
        driverName: String,
        driverPhone: String,
        driverWhatsapp: String
    ) async throws {
        _ = try await functions.httpsCallable("claimRideAsDriver").call([
            "rideId": ride.id.uuidString,
            "displayName": driverName,
            "phone": driverPhone,
            "whatsapp": driverWhatsapp,
        ])
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
        _ = try await functions.httpsCallable("cancelManagedRide").call([
            "rideId": ride.id.uuidString,
            "reason": reason as Any,
        ])
    }

    // MARK: - Complete Ride

    /// Completes the ride.
    /// Validates: actor is assigned driver, ride is in rideStarted state.
    func completeRide(_ ride: Ride) async throws {
        _ = try await functions.httpsCallable("advanceRideStatus").call([
            "rideId": ride.id.uuidString,
            "status": "completed",
        ])
    }

    // MARK: - Expire Stale Ride (client-side, called by rider listener)

    /// Marks a posted ride as expired when its hot window has passed.
    /// Only called for rides owned by the current user — no ownership check needed.
    func expireRide(_ ride: Ride) async {
        guard ride.status == .posted, !ride.isHot else { return }
        let rideRef = db.collection("rides").document(ride.id.uuidString)
        let now = Timestamp(date: Date())
        try? await rideRef.updateData(["status": "expired", "updatedAt": now])
    }
}



// MARK: - Errors

enum RideServiceError: LocalizedError {
    case notAuthenticated
    case notAuthorized
    case missingDriver
    case cancelNotAllowed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:  return "You must be signed in to perform this action."
        case .notAuthorized:     return "You are not authorized to perform this action."
        case .missingDriver:     return "No driver assigned to this ride."
        case .cancelNotAllowed:  return "This ride cannot be cancelled at its current stage."
        }
    }
}
