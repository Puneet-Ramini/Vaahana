//
//  RideBid.swift
//  Vaahana
//
//  Bid entity — stored at rides/{rideId}/bids/{bidId}
//

import Foundation
import FirebaseFirestore

// MARK: - Bid Status

enum BidStatus: String, Codable {
    case active     // visible to rider, can be chosen
    case selected   // rider chose this bid — ride becomes accepted
    case rejected   // rider chose someone else
    case withdrawn  // driver cancelled their bid
    case expired    // ride expired or was cancelled before selection
}

// MARK: - RideBid

struct RideBid: Identifiable, Codable, Equatable {
    var id: String           // UUID string, also used as Firestore document ID
    var rideId: String
    var driverId: String
    var driverName: String
    var driverPhone: String
    var driverWhatsapp: String
    var bidCoins: Int
    var message: String?
    var status: BidStatus
    var createdAt: Date
    var updatedAt: Date?

    // MARK: Computed

    var timeAgo: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: createdAt, relativeTo: Date())
    }

    var initials: String {
        let parts = driverName.split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(driverName.prefix(2)).uppercased()
    }

    // MARK: Custom Decoder

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = (try? c.decodeIfPresent(String.self, forKey: .id))             ?? UUID().uuidString
        rideId         = (try? c.decodeIfPresent(String.self, forKey: .rideId))         ?? ""
        driverId       = (try? c.decodeIfPresent(String.self, forKey: .driverId))       ?? ""
        driverName     = (try? c.decodeIfPresent(String.self, forKey: .driverName))     ?? ""
        driverPhone    = (try? c.decodeIfPresent(String.self, forKey: .driverPhone))    ?? ""
        driverWhatsapp = (try? c.decodeIfPresent(String.self, forKey: .driverWhatsapp)) ?? ""
        bidCoins       = (try? c.decodeIfPresent(Int.self, forKey: .bidCoins))          ?? 0
        message        = try? c.decodeIfPresent(String.self, forKey: .message)
        status         = (try? c.decodeIfPresent(BidStatus.self, forKey: .status))      ?? .active
        createdAt      = (try? c.decodeIfPresent(Date.self, forKey: .createdAt))        ?? Date()
        updatedAt      = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}
