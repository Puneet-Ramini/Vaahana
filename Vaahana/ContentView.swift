//
//  ContentView.swift
//  Vaahana
//
//  Created by Puneet Ramini on 4/6/26.
//

import SwiftUI
import Combine
import MapKit
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

// MARK: - Data Models

// MARK: RideStatus — full state machine
enum RideStatus: String, Codable {
    case posted
    case accepted
    case driverEnroute  = "driver_enroute"
    case driverArrived  = "driver_arrived"
    case rideStarted    = "ride_started"
    case completed
    case cancelled
    case expired

    // Backward compat: old Firestore docs stored "pending" — map to .posted
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == "pending" { self = .posted; return }
        self = RideStatus(rawValue: raw) ?? .posted
    }

    var isActive: Bool {
        switch self {
        case .accepted, .driverEnroute, .driverArrived, .rideStarted: return true
        default: return false
        }
    }

    var isFinal: Bool {
        switch self {
        case .completed, .cancelled, .expired: return true
        default: return false
        }
    }

    var riderDisplayText: String {
        switch self {
        case .posted:        return "Waiting for driver"
        case .accepted:      return "Driver accepted"
        case .driverEnroute: return "Driver on the way"
        case .driverArrived: return "Driver arrived"
        case .rideStarted:   return "Ride in progress"
        case .completed:     return "Completed"
        case .cancelled:     return "Cancelled"
        case .expired:       return "Expired"
        }
    }

    var driverDisplayText: String {
        switch self {
        case .posted:        return "Open request"
        case .accepted:      return "Accepted"
        case .driverEnroute: return "En route"
        case .driverArrived: return "Arrived"
        case .rideStarted:   return "In progress"
        case .completed:     return "Completed"
        case .cancelled:     return "Cancelled"
        case .expired:       return "Expired"
        }
    }
}

// MARK: CoinStatus — lifecycle of coins for a ride
enum CoinStatus: String, Codable {
    case none
    case locked       // locked from rider at acceptance
    case transferred  // transferred to driver at completion
    case refunded     // unlocked back to rider on cancellation
}

// MARK: UserRole
enum UserRole: String, Codable {
    case rider
    case driver
}

// MARK: Ride
struct Ride: Identifiable, Codable, Equatable {
    // Core identity
    var id: UUID
    var riderId: String
    var status: RideStatus
    var createdAt: Date
    var updatedAt: Date?

    // Rider contact
    var name: String
    var phone: String
    var phoneCountryCode: String
    var whatsappPhone: String
    var whatsappCountryCode: String

    // Route
    var from: String
    var to: String
    var miles: Double
    var pickupLat: Double?     // geocoded at post time
    var pickupLng: Double?
    var source: String?

    // Details
    var coins: Int
    var hotDuration: Int       // minutes the request stays visible
    var pickupDate: Date

    // Driver assignment (populated on acceptance)
    var driverId: String?
    var driverName: String?
    var driverPhone: String?
    var driverWhatsapp: String?

    // Coin lifecycle
    var coinStatus: CoinStatus
    var coinsLocked: Int
    var coinsTransferred: Int

    // State timestamps
    var acceptedAt: Date?
    var driverEnrouteAt: Date?
    var arrivedAt: Date?
    var startedAt: Date?
    var completedAt: Date?
    var cancelledAt: Date?

    // Cancellation
    var cancelledBy: String?
    var cancellationReasonCode: String?

    // Bid marketplace summary (denormalized for quick display)
    var bidCount: Int
    var selectedBidId: String?
    var finalCoins: Int?          // agreed coin amount after bid selection
    var lowestBidCoins: Int?
    var latestBidAt: Date?

    // MARK: Computed

    var hotUntil: Date { createdAt.addingTimeInterval(TimeInterval(hotDuration * 60)) }
    var isHot: Bool { hotUntil > Date() }

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var timeAgo: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: createdAt, relativeTo: Date())
    }

    var pickupDateFormatted: String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: pickupDate)
    }

    var pickupDateShort: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: pickupDate)
    }

    // MARK: Convenience init (for creating new rides)

    init(
        id: UUID = UUID(),
        riderId: String,
        name: String,
        phone: String,
        phoneCountryCode: String,
        whatsappPhone: String,
        whatsappCountryCode: String,
        from: String,
        to: String,
        miles: Double,
        pickupLat: Double? = nil,
        pickupLng: Double? = nil,
        source: String? = "app",
        coins: Int,
        hotDuration: Int = 5,
        pickupDate: Date,
        status: RideStatus = .posted,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.riderId = riderId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = nil
        self.name = name
        self.phone = phone
        self.phoneCountryCode = phoneCountryCode
        self.whatsappPhone = whatsappPhone
        self.whatsappCountryCode = whatsappCountryCode
        self.from = from
        self.to = to
        self.miles = miles
        self.pickupLat = pickupLat
        self.pickupLng = pickupLng
        self.source = source
        self.coins = coins
        self.hotDuration = hotDuration
        self.pickupDate = pickupDate
        self.driverId = nil
        self.driverName = nil
        self.driverPhone = nil
        self.driverWhatsapp = nil
        self.coinStatus = .none
        self.coinsLocked = 0
        self.coinsTransferred = 0
        self.acceptedAt = nil
        self.driverEnrouteAt = nil
        self.arrivedAt = nil
        self.startedAt = nil
        self.completedAt = nil
        self.cancelledAt = nil
        self.cancelledBy = nil
        self.cancellationReasonCode = nil
        self.bidCount = 0
        self.selectedBidId = nil
        self.finalCoins = nil
        self.lowestBidCoins = nil
        self.latestBidAt = nil
    }

    // MARK: Custom Decoder — backward compat with old Firestore docs

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Try field "id" first; fall back to Firestore document ID injected as "_id" by the SDK
        if let uuid = try? c.decodeIfPresent(UUID.self, forKey: .id) {
            id = uuid
        } else if let str = try? c.decodeIfPresent(String.self, forKey: .id),
                  let uuid = UUID(uuidString: str) {
            id = uuid
        } else {
            id = UUID()   // generate stable fallback so doc still appears
        }
        riderId                = (try? c.decodeIfPresent(String.self, forKey: .riderId))              ?? ""
        status                 = (try? c.decodeIfPresent(RideStatus.self, forKey: .status))            ?? .posted
        createdAt              = (try? c.decodeIfPresent(Date.self, forKey: .createdAt))               ?? Date()
        updatedAt              = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        name                   = (try? c.decodeIfPresent(String.self, forKey: .name))                  ?? ""
        phone                  = (try? c.decodeIfPresent(String.self, forKey: .phone))                 ?? ""
        phoneCountryCode       = (try? c.decodeIfPresent(String.self, forKey: .phoneCountryCode))      ?? "+1"
        whatsappPhone          = (try? c.decodeIfPresent(String.self, forKey: .whatsappPhone))         ?? ""
        whatsappCountryCode    = (try? c.decodeIfPresent(String.self, forKey: .whatsappCountryCode))   ?? "+1"
        from                   = (try? c.decodeIfPresent(String.self, forKey: .from))                  ?? ""
        to                     = (try? c.decodeIfPresent(String.self, forKey: .to))                    ?? ""
        miles                  = (try? c.decodeIfPresent(Double.self, forKey: .miles))                 ?? 0
        pickupLat              = try? c.decodeIfPresent(Double.self, forKey: .pickupLat)
        pickupLng              = try? c.decodeIfPresent(Double.self, forKey: .pickupLng)
        source                 = try? c.decodeIfPresent(String.self, forKey: .source)
        coins                  = (try? c.decodeIfPresent(Int.self, forKey: .coins))                    ?? 0
        hotDuration            = (try? c.decodeIfPresent(Int.self, forKey: .hotDuration))              ?? 5
        pickupDate             = (try? c.decodeIfPresent(Date.self, forKey: .pickupDate))              ?? Date()
        driverId               = try? c.decodeIfPresent(String.self, forKey: .driverId)
        driverName             = try? c.decodeIfPresent(String.self, forKey: .driverName)
        driverPhone            = try? c.decodeIfPresent(String.self, forKey: .driverPhone)
        driverWhatsapp         = try? c.decodeIfPresent(String.self, forKey: .driverWhatsapp)
        coinStatus             = (try? c.decodeIfPresent(CoinStatus.self, forKey: .coinStatus))        ?? .none
        coinsLocked            = (try? c.decodeIfPresent(Int.self, forKey: .coinsLocked))              ?? 0
        coinsTransferred       = (try? c.decodeIfPresent(Int.self, forKey: .coinsTransferred))         ?? 0
        acceptedAt             = try? c.decodeIfPresent(Date.self, forKey: .acceptedAt)
        driverEnrouteAt        = try? c.decodeIfPresent(Date.self, forKey: .driverEnrouteAt)
        arrivedAt              = try? c.decodeIfPresent(Date.self, forKey: .arrivedAt)
        startedAt              = try? c.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt            = try? c.decodeIfPresent(Date.self, forKey: .completedAt)
        cancelledAt            = try? c.decodeIfPresent(Date.self, forKey: .cancelledAt)
        cancelledBy            = try? c.decodeIfPresent(String.self, forKey: .cancelledBy)
        cancellationReasonCode = try? c.decodeIfPresent(String.self, forKey: .cancellationReasonCode)
        bidCount               = (try? c.decodeIfPresent(Int.self, forKey: .bidCount))         ?? 0
        selectedBidId          = try? c.decodeIfPresent(String.self, forKey: .selectedBidId)
        finalCoins             = try? c.decodeIfPresent(Int.self, forKey: .finalCoins)
        lowestBidCoins         = try? c.decodeIfPresent(Int.self, forKey: .lowestBidCoins)
        latestBidAt            = try? c.decodeIfPresent(Date.self, forKey: .latestBidAt)
    }

    var isWhatsAppSource: Bool {
        (source ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "whatsapp"
    }
}

// MARK: - Storage Manager

class RideStorage: ObservableObject {
    /// Rider's own rides (all statuses), sorted newest first
    @Published var myRides: [Ride] = []
    /// Posted rides visible to drivers (status == .posted)
    @Published var postedRides: [Ride] = []
    /// Current active ride for either role (non-final, non-posted status)
    @Published var activeRide: Ride? = nil
    @Published var isLoading = true

    /// Set to a ride that just transitioned to .completed — consumed by the views to show a rating prompt.
    @Published var recentlyCompletedRide: Ride? = nil
    /// Tracks previous status per ride so we can detect transitions inside snapshot listeners.
    private var prevStatuses: [UUID: RideStatus] = [:]

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var distanceCalcInFlight: Set<UUID> = []

    let uid: String
    let role: UserRole

    init(role: UserRole) {
        self.role = role
        self.uid = Auth.auth().currentUser?.uid ?? ""
        startListening()
    }

    deinit {
        listeners.forEach { $0.remove() }
    }

    private func startListening() {
        if role == .rider {
            // Rider sees their own rides, keyed by riderId
            let l = db.collection("rides")
                .whereField("riderId", isEqualTo: uid)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self, let snapshot else { return }
                    let rides = snapshot.documents.compactMap { try? $0.data(as: Ride.self) }
                    self.myRides = rides.sorted { $0.createdAt > $1.createdAt }
                    self.activeRide = rides.first { $0.status.isActive }
                    self.isLoading = false

                    // Detect rides that just completed → trigger rating prompt
                    for ride in rides {
                        if self.prevStatuses[ride.id] != .completed && ride.status == .completed {
                            self.recentlyCompletedRide = ride
                        }
                        self.prevStatuses[ride.id] = ride.status
                    }

                    // Client-side expiry: mark stale posted rides as expired
                    for ride in rides where ride.status == .posted && !ride.isHot {
                        Task { await RideService.shared.expireRide(ride) }
                    }
                }
            listeners.append(l)
        } else {
            // Driver sees all posted (hot) rides
            let l = db.collection("rides")
                .whereField("status", isEqualTo: "posted")
                .addSnapshotListener { [weak self] snapshot, error in
                    guard let self else { return }
                    if let error {
                        print("[RideStorage] snapshot error: \(error)")
                        return
                    }
                    guard let snapshot else { return }
                    var decoded: [Ride] = []
                    for doc in snapshot.documents {
                        do {
                            let ride = try doc.data(as: Ride.self)
                            decoded.append(ride)
                        } catch {
                            // Log which doc and why so we can fix the decoder
                            print("[RideStorage] decode failed docID=\(doc.documentID) from=\(doc.data()["from"] ?? "?") error=\(error)")
                        }
                    }
                    self.postedRides = self.deduplicatePostedRides(decoded)
                    self.isLoading = false
                    self.backfillMissingMilesIfNeeded(in: self.postedRides)
                }
            listeners.append(l)

            // Driver also listens for any ride they've accepted
            let l2 = db.collection("rides")
                .whereField("driverId", isEqualTo: uid)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self, let snapshot else { return }
                    let driverRides = snapshot.documents.compactMap { try? $0.data(as: Ride.self) }
                    self.activeRide = driverRides.first { $0.status.isActive }

                    // Detect rides that just completed → trigger rating prompt
                    for ride in driverRides {
                        if self.prevStatuses[ride.id] != .completed && ride.status == .completed {
                            self.recentlyCompletedRide = ride
                        }
                        self.prevStatuses[ride.id] = ride.status
                    }
                }
            listeners.append(l2)
        }
    }

    func addRide(_ ride: Ride) {
        try? db.collection("rides").document(ride.id.uuidString).setData(from: ride)
    }

    func updateRide(_ ride: Ride) {
        try? db.collection("rides").document(ride.id.uuidString).setData(from: ride)
    }

    func deleteRide(_ ride: Ride) {
        db.collection("rides").document(ride.id.uuidString).delete()
    }

    /// Hot posted rides — used by driver discovery
    var hotPostedRides: [Ride] {
        postedRides.filter { $0.isHot }
    }

    private func deduplicatePostedRides(_ rides: [Ride]) -> [Ride] {
        var unique: [String: Ride] = [:]
        let calendar = Calendar.current

        for ride in rides {
            let key: String
            if ride.isWhatsAppSource {
                let pickupDay = calendar.startOfDay(for: ride.pickupDate).timeIntervalSince1970
                let phone = "\(ride.whatsappCountryCode)\(ride.whatsappPhone)"
                key = [
                    "whatsapp",
                    phone.lowercased(),
                    ride.from.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    ride.to.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    String(Int(pickupDay))
                ].joined(separator: "|")
            } else {
                key = ride.id.uuidString
            }

            if let existing = unique[key] {
                let existingHasCoords = existing.pickupLat != nil && existing.pickupLng != nil
                let incomingHasCoords = ride.pickupLat != nil && ride.pickupLng != nil

                if ride.createdAt > existing.createdAt || (incomingHasCoords && !existingHasCoords) {
                    unique[key] = ride
                }
            } else {
                unique[key] = ride
            }
        }

        return unique.values.sorted { $0.createdAt > $1.createdAt }
    }

    private func backfillMissingMilesIfNeeded(in rides: [Ride]) {
        let candidates = rides.filter {
            $0.miles <= 0 &&
            !$0.from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !distanceCalcInFlight.contains($0.id)
        }

        for ride in candidates {
            distanceCalcInFlight.insert(ride.id)
            Task { [weak self] in
                guard let self else { return }
                defer { self.distanceCalcInFlight.remove(ride.id) }

                do {
                    let calc = DistanceCalculator()
                    let computed = try await calc.calculateDistance(from: ride.from, to: ride.to)
                    let miles = max(0, (computed * 10).rounded() / 10)

                    await MainActor.run {
                        if let index = self.postedRides.firstIndex(where: { $0.id == ride.id }) {
                            self.postedRides[index].miles = miles
                        }
                    }

                    try? await self.db.collection("rides").document(ride.id.uuidString)
                        .setData(["miles": miles], merge: true)
                } catch {
                    // Keep feed responsive; we'll retry on a future snapshot.
                }
            }
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    let role: UserRole
    @StateObject private var storage: RideStorage
    @EnvironmentObject var userState: UserState
    @State private var showingProfile = false
    @State private var showingAdmin   = false

    init(role: UserRole) {
        self.role = role
        _storage = StateObject(wrappedValue: RideStorage(role: role))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Vaahana")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                Spacer()
                if userState.isAdmin {
                    Button { showingAdmin = true } label: {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.title2)
                            .foregroundStyle(.orange)
                    }
                    .padding(.trailing, 6)
                }
                Button {
                    showingProfile = true
                } label: {
                    Image(systemName: "person.circle.fill")
                        .font(.title)
                        .foregroundStyle(.primary)
                }
                .padding(.trailing)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(Color(UIColor.systemBackground))

            // Role-locked content
            if role == .rider {
                RiderView()
            } else {
                DriverView()
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .environmentObject(storage)
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
        .sheet(isPresented: $showingAdmin) {
            AdminView()
        }
    }
}

// MARK: - Rider View

struct RiderView: View {
    @EnvironmentObject var storage: RideStorage
    @State private var showingPostSheet = false
    @State private var editingRide: Ride?
    @State private var showingActiveRide = false
    @State private var viewingBidsRide: Ride?
    @State private var ratingRide: Ride?

    var pastRides: [Ride] {
        storage.myRides.filter { $0.status.isFinal }
    }

    var postedRides: [Ride] {
        storage.myRides.filter { $0.status == .posted }
    }

    var body: some View {
        ZStack {
            if storage.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Active ride banner (if any)
                        if let active = storage.activeRide {
                            activeRideBanner(active)
                        }

                        // Posted (hot) requests
                        if postedRides.isEmpty && storage.activeRide == nil {
                            emptyState
                        } else {
                            ForEach(postedRides) { ride in
                                RideCard(ride: ride, isDriverMode: false, onEdit: {
                                    editingRide = ride
                                }, onDelete: {
                                    storage.deleteRide(ride)
                                }, onViewBids: {
                                    viewingBidsRide = ride
                                })
                            }
                        }

                        // Past rides section
                        if !pastRides.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Past Rides")
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                ForEach(pastRides) { ride in
                                    RideCard(ride: ride, isDriverMode: false, onEdit: nil, onDelete: nil)
                                }
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 80)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if storage.activeRide == nil {
                Button {
                    showingPostSheet = true
                } label: {
                    Text("+ Request a Ride")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black)
                        .cornerRadius(12)
                }
                .padding()
                .background(Color(UIColor.systemGroupedBackground))
            }
        }
        .sheet(isPresented: $showingPostSheet) { PostRideSheet() }
        .sheet(item: $editingRide) { ride in PostRideSheet(editingRide: ride) }
        .sheet(isPresented: $showingActiveRide) {
            if let active = storage.activeRide {
                ActiveRideView(ride: active, role: .rider)
            }
        }
        .sheet(item: $viewingBidsRide) { ride in
            BidListView(ride: ride)
        }
        .sheet(item: $ratingRide) { ride in
            RatingView(ride: ride, raterRole: .rider, targetUid: ride.driverId ?? "")
                .onDisappear {
                    UserDefaults.standard.set(true, forKey: "rated_rider_\(ride.id.uuidString)")
                    storage.recentlyCompletedRide = nil
                }
        }
        .onChange(of: storage.recentlyCompletedRide) { _, ride in
            guard let ride, let driverId = ride.driverId, !driverId.isEmpty else { return }
            let key = "rated_rider_\(ride.id.uuidString)"
            if !UserDefaults.standard.bool(forKey: key) { ratingRide = ride }
        }
    }

    private func activeRideBanner(_ ride: Ride) -> some View {
        Button { showingActiveRide = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "car.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ride in Progress").font(.caption).foregroundStyle(.secondary)
                    Text(ride.status.riderDisplayText)
                        .font(.headline).foregroundStyle(.blue)
                    Text("\(ride.from) → \(ride.to)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.08))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("🚗").font(.system(size: 72))
            Text("No requests yet").font(.headline)
            Text("Post your first ride request.\nDrivers nearby will reach out.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Driver View

private enum DriverFeedTab: String, CaseIterable, Identifiable {
    case all = "All"
    case whatsApp = "WhatsApp"

    var id: String { rawValue }
}

struct DriverView: View {
    @EnvironmentObject var storage: RideStorage
    @State private var selectedRide: Ride?
    @State private var isOnline = true
    @State private var showingActiveRide = false
    @State private var showingMyBids = false
    @State private var ratingRide: Ride?
    @State private var selectedFeedTab: DriverFeedTab = .all
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var panelHeight: CGFloat = 0
    @GestureState private var panelDragTranslation: CGFloat = 0
    @EnvironmentObject private var locationService: LocationService

    // Persisted filter settings
    @AppStorage("filterRadius") private var filterRadius = 5.0
    @AppStorage("driverCenterLat") private var driverCenterLat: Double = 0
    @AppStorage("driverCenterLon") private var driverCenterLon: Double = 0
    @AppStorage("driverCenterCustom") private var driverCenterCustom: Bool = false

    var effectiveCenter: CLLocationCoordinate2D? {
        if driverCenterCustom {
            return CLLocationCoordinate2D(latitude: driverCenterLat, longitude: driverCenterLon)
        }
        return locationService.location?.coordinate
    }

    var radiusMeters: CLLocationDistance { filterRadius * 1609.34 }

    private var sourceFilteredRides: [Ride] {
        let hot = storage.hotPostedRides
        switch selectedFeedTab {
        case .all:
            return hot
        case .whatsApp:
            return hot.filter(\.isWhatsAppSource)
        }
    }

    private var mapCenter: CLLocationCoordinate2D? {
        if selectedFeedTab == .whatsApp {
            return locationService.location?.coordinate
        }
        return effectiveCenter
    }

    var filteredRides: [(ride: Ride, distanceMiles: Double?)] {
        guard isOnline else { return [] }
        guard let center = mapCenter else {
            if selectedFeedTab == .whatsApp {
                return []
            }
            return sourceFilteredRides.map { ($0, nil) }
        }

        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return sourceFilteredRides
            .compactMap { ride -> (ride: Ride, distanceMiles: Double?)? in
                guard let lat = ride.pickupLat, let lng = ride.pickupLng else {
                    // WhatsApp tab stays strictly location-based.
                    if selectedFeedTab == .whatsApp {
                        return nil
                    }
                    // No coords yet (geocoding pending) — show in list without distance.
                    return (ride, nil)
                }
                let dist = centerLoc.distance(from: CLLocation(latitude: lat, longitude: lng)) / 1609.34
                guard dist <= filterRadius else { return nil }
                return (ride, dist)
            }
            .sorted {
                // Rides with known coords come before unknown; among known, sort by distance
                switch ($0.distanceMiles, $1.distanceMiles) {
                case let (a?, b?): return a < b
                case (_?, nil):   return true
                case (nil, _?):   return false
                default:          return $0.ride.hotUntil > $1.ride.hotUntil
                }
            }
    }
    
    private var locationKey: String {
        if let loc = locationService.location {
            return String(format: "%.6f,%.6f", loc.coordinate.latitude, loc.coordinate.longitude)
        }
        return ""
    }

    private var emptyStateMessage: String {
        if selectedFeedTab == .whatsApp {
            if locationService.location == nil {
                return "Enable location to view nearby WhatsApp requests."
            }
            if sourceFilteredRides.isEmpty {
                return "No WhatsApp requests right now."
            }
            return "No WhatsApp requests within \(Int(filterRadius)) mi of your current location."
        }

        if sourceFilteredRides.isEmpty {
            return "No hot requests right now"
        }
        return "No hot requests within \(Int(filterRadius)) mi — expand radius or tap the map to move search area"
    }

    private func snappedPanelHeight(_ proposed: CGFloat, snapHeights: [CGFloat]) -> CGFloat {
        guard let minHeight = snapHeights.min(), let maxHeight = snapHeights.max() else {
            return proposed
        }
        let clamped = min(max(proposed, minHeight), maxHeight)
        return snapHeights.min(by: { abs($0 - clamped) < abs($1 - clamped) }) ?? clamped
    }

    var body: some View {
        GeometryReader { geo in
            let snapHeights: [CGFloat] = [
                geo.size.height * 0.38,
                geo.size.height * 0.62,
                geo.size.height * 0.86
            ]
            let minPanelHeight = snapHeights[0]
            let maxPanelHeight = snapHeights[2]
            let resolvedPanelHeight = panelHeight == 0 ? snapHeights[1] : panelHeight
            let currentPanelHeight = min(max(resolvedPanelHeight + panelDragTranslation, minPanelHeight), maxPanelHeight)

            ZStack(alignment: .bottom) {
                // ── Map (fixed height for smooth sheet dragging) ──
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        // Live location dot
                        if let loc = locationService.location {
                            Annotation("Me", coordinate: loc.coordinate) {
                                ZStack {
                                    Circle().fill(Color.blue.opacity(0.25)).frame(width: 36, height: 36)
                                    Circle().fill(Color.blue).frame(width: 16, height: 16)
                                    Circle().stroke(Color.white, lineWidth: 2.5).frame(width: 16, height: 16)
                                }
                                .shadow(color: .blue.opacity(0.4), radius: 6)
                            }
                        }

                        // Drive-radius circle overlay
                        if let center = mapCenter {
                            MapCircle(center: center, radius: radiusMeters)
                                .foregroundStyle(Color.blue.opacity(0.1))
                                .stroke(Color.blue, lineWidth: 2)

                            // Custom-center pin
                            if driverCenterCustom && selectedFeedTab == .all {
                                Annotation("Drive Area", coordinate: center) {
                                    ZStack {
                                        Circle().fill(Color.blue).frame(width: 34, height: 34)
                                        Image(systemName: "scope")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                    .shadow(radius: 4)
                                }
                            }
                        }

                        // Ride pins (using stored geocoded coords)
                        ForEach(filteredRides, id: \.ride.id) { item in
                            if let lat = item.ride.pickupLat, let lng = item.ride.pickupLng {
                                Annotation(item.ride.from, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                                    rideAnnotationView(for: item.ride)
                                }
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                    }
                    .onTapGesture { screenPoint in
                        guard selectedFeedTab == .all else { return }
                        if let coord = proxy.convert(screenPoint, from: .local) {
                            driverCenterLat = coord.latitude
                            driverCenterLon = coord.longitude
                            driverCenterCustom = true
                            withAnimation {
                                cameraPosition = .region(MKCoordinateRegion(
                                    center: coord,
                                    latitudinalMeters: radiusMeters * 3,
                                    longitudinalMeters: radiusMeters * 3
                                ))
                            }
                        }
                    }
                }
                .frame(height: geo.size.height)

                // ── Bottom control panel ──
                controlPanel(minHeight: minPanelHeight, maxHeight: maxPanelHeight, snapHeights: snapHeights)
                    .frame(height: maxPanelHeight)
                    .offset(y: maxPanelHeight - currentPanelHeight)
            }
            .onAppear {
                if panelHeight == 0 {
                    panelHeight = snapHeights[1]
                }
            }
        }
        .onChange(of: locationKey) { _ in
            if selectedFeedTab == .whatsApp, let loc = locationService.location {
                cameraPosition = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    latitudinalMeters: radiusMeters * 3,
                    longitudinalMeters: radiusMeters * 3
                ))
                return
            }

            guard !driverCenterCustom, let loc = locationService.location else { return }
            cameraPosition = .region(MKCoordinateRegion(
                center: loc.coordinate,
                latitudinalMeters: radiusMeters * 3,
                longitudinalMeters: radiusMeters * 3
            ))
        }
        .onChange(of: selectedFeedTab) { _, tab in
            if tab == .whatsApp {
                driverCenterCustom = false
                if let loc = locationService.location {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: loc.coordinate,
                        latitudinalMeters: radiusMeters * 3,
                        longitudinalMeters: radiusMeters * 3
                    ))
                }
            }
        }
        .sheet(item: $selectedRide) { ride in RideDetailSheet(ride: ride) }
        .sheet(isPresented: $showingActiveRide) {
            if let active = storage.activeRide {
                ActiveRideView(ride: active, role: .driver)
            }
        }
        .sheet(isPresented: $showingMyBids) {
            DriverBidsView()
        }
        .sheet(item: $ratingRide) { ride in
            RatingView(ride: ride, raterRole: .driver, targetUid: ride.riderId)
                .onDisappear {
                    UserDefaults.standard.set(true, forKey: "rated_driver_\(ride.id.uuidString)")
                    storage.recentlyCompletedRide = nil
                }
        }
        .onChange(of: storage.recentlyCompletedRide) { _, ride in
            guard let ride else { return }
            let key = "rated_driver_\(ride.id.uuidString)"
            if !UserDefaults.standard.bool(forKey: key) { ratingRide = ride }
        }
    }

    // MARK: - Control Panel

    private func controlPanel(minHeight: CGFloat, maxHeight: CGFloat, snapHeights: [CGFloat]) -> some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .updating($panelDragTranslation) { value, state, _ in
                            state = -value.translation.height
                        }
                        .onEnded { value in
                            let projectedHeight = panelHeight - value.translation.height
                            let snapped = snappedPanelHeight(projectedHeight, snapHeights: snapHeights)
                            withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
                                panelHeight = snapped
                            }
                        }
                )

            // Active ride banner
            if let active = storage.activeRide {
                Button { showingActiveRide = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "car.circle.fill")
                            .font(.title2).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active Ride").font(.caption).foregroundStyle(.secondary)
                            Text(active.status.driverDisplayText).font(.subheadline).fontWeight(.semibold).foregroundStyle(.blue)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal).padding(.vertical, 10)
                    .background(Color.blue.opacity(0.08))
                }
                .buttonStyle(.plain)
                Divider()
            }

            // My Bids shortcut
            Button { showingMyBids = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.title3).foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("My Bids").font(.subheadline).fontWeight(.semibold)
                        Text("Track bids you've placed").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal).padding(.vertical, 10)
                .background(Color.purple.opacity(0.07))
            }
            .buttonStyle(.plain)
            Divider()

            // Online / Offline toggle
            HStack {
                Label(isOnline ? "Online" : "Offline", systemImage: isOnline ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(isOnline ? .green : .secondary)
                Spacer()
                Toggle("", isOn: $isOnline)
                    .labelsHidden()
                    .tint(.green)
                    .onChange(of: isOnline) { _, online in
                        guard let uid = Auth.auth().currentUser?.uid else { return }
                        Firestore.firestore().collection("users").document(uid)
                            .setData(["isAvailable": online], merge: true)
                    }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            Picker("Feed", selection: $selectedFeedTab) {
                Text("All").tag(DriverFeedTab.all)
                Text("WhatsApp").tag(DriverFeedTab.whatsApp)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Location + radius
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Image(systemName: (driverCenterCustom && selectedFeedTab == .all) ? "mappin.circle.fill" : "location.fill")
                                .foregroundStyle((driverCenterCustom && selectedFeedTab == .all) ? .orange : .blue)
                            Text((driverCenterCustom && selectedFeedTab == .all) ? "Custom Location" : "Live Location")
                                .font(.subheadline).fontWeight(.semibold)
                        }
                        Text(selectedFeedTab == .whatsApp
                             ? "WhatsApp rides are filtered strictly from your current location"
                             : (driverCenterCustom
                                ? "Tap the map to move your search area"
                                : "Tap anywhere on the map to pin a location"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if driverCenterCustom && selectedFeedTab == .all {
                        Button {
                            driverCenterCustom = false
                            if let loc = locationService.location {
                                withAnimation {
                                    cameraPosition = .region(MKCoordinateRegion(
                                        center: loc.coordinate,
                                        latitudinalMeters: radiusMeters * 3,
                                        longitudinalMeters: radiusMeters * 3
                                    ))
                                }
                            }
                        } label: {
                            Label("Live", systemImage: "location.fill")
                                .font(.caption).fontWeight(.semibold)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.blue).foregroundStyle(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)

                // Radius slider
                VStack(spacing: 4) {
                    HStack {
                        Text("Search radius").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(filterRadius)) miles")
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.blue)
                    }
                    Slider(value: $filterRadius, in: 1...50, step: 1).tint(.blue)
                }
                .padding(.horizontal)
            }

            Divider().padding(.top, 8)

            // Rides header
            HStack {
                Text(selectedFeedTab == .whatsApp ? "📲 WhatsApp Requests" : "🔥 Hot Requests")
                    .font(.subheadline).fontWeight(.semibold)
                Text("(\(filteredRides.count))").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Rides list / empty state
            if storage.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else if filteredRides.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: sourceFilteredRides.isEmpty ? "flame.slash" : "map.circle")
                        .font(.title2).foregroundStyle(.secondary)
                    Text(emptyStateMessage)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredRides, id: \.ride.id) { item in
                            CompactRideRow(ride: item.ride, distanceMiles: item.distanceMiles) {
                                selectedRide = item.ride
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Map Annotation

    private func rideAnnotationView(for ride: Ride) -> some View {
        // Heat: 1.0 = just posted (bright), 0.0 = about to expire (dim)
        let heat = max(0, min(1, ride.hotUntil.timeIntervalSinceNow / Double(ride.hotDuration * 60)))
        // Interpolate: hot=red/orange → cool=gray/blue
        let pinColor = Color(
            hue:        Double(0.08 - 0.08 * (1 - heat)),   // orange (0.08) → red (0.0)
            saturation: Double(0.9),
            brightness: Double(0.5 + 0.5 * heat)             // dim when cold
        )
        let size: CGFloat = 36 + 10 * heat                   // bigger when hotter

        return Button { selectedRide = ride } label: {
            ZStack {
                Circle()
                    .fill(pinColor)
                    .frame(width: size, height: size)
                    .shadow(color: pinColor.opacity(heat > 0.6 ? 0.7 : 0.2), radius: heat > 0.6 ? 8 : 3)
                VStack(spacing: 1) {
                    Image(systemName: "figure.wave")
                        .font(.system(size: size * 0.3)).foregroundStyle(.white)
                    if ride.coins > 0 {
                        Text("🪙\(ride.coins)")
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                    }
                }
                if ride.isWhatsAppSource {
                    VStack {
                        HStack {
                            Spacer()
                            Text("WA")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .clipShape(Capsule())
                                .offset(x: 6, y: -6)
                        }
                        Spacer()
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

}

// MARK: - Compact Ride Row

struct CompactRideRow: View {
    let ride: Ride
    var distanceMiles: Double? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Distance badge
                if let dist = distanceMiles {
                    VStack(spacing: 1) {
                        Text(dist < 0.1 ? "<0.1" : String(format: dist < 10 ? "%.1f" : "%.0f", dist))
                            .font(.system(size: 13, weight: .bold))
                        Text("mi")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(dist < 2 ? .green : dist < 10 ? .orange : .secondary)
                    .frame(width: 36)
                }

                // From -> To
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(ride.from)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(ride.to)
                            .font(.subheadline)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(ride.pickupDateShort)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        if ride.isWhatsAppSource, let distanceMiles {
                            Text("\(distanceMiles < 0.1 ? "<0.1" : String(format: "%.1f", distanceMiles)) mi away")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                            Text("•").foregroundStyle(.secondary)
                        }
                        if ride.miles > 0 {
                            Text("\(String(format: "%.1f", ride.miles)) mi route")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("•").foregroundStyle(.secondary)
                        }
                        if ride.isWhatsAppSource {
                            Text("WhatsApp")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Text("🪙 \(ride.coins)")
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.orange)
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            let rem = ride.hotUntil.timeIntervalSince(ctx.date)
                            if rem > 0 {
                                Text("🔥 \(Int(rem/60)):\(String(format:"%02d", Int(rem)%60))")
                                    .font(.caption2).foregroundStyle(.orange)
                            } else {
                                Text("Expired").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Status indicator
                Circle()
                    .fill(ride.status == .posted ? Color.black : Color.green)
                    .frame(width: 8, height: 8)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(10)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ride Detail Sheet

struct RideDetailSheet: View {
    let ride: Ride
    @EnvironmentObject var storage: RideStorage
    @Environment(\.dismiss) var dismiss
    @State private var showingBidSheet = false
    @State private var existingBid: RideBid?
    @State private var isLoadingBid = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Route
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("From")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(ride.from)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                            
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("To")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(ride.to)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                        }
                        
                        // Pickup Time
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pickup Time")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(ride.pickupDateFormatted)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                        }
                        
                        // Stats
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Distance")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(String(format: "%.1f", ride.miles)) miles")
                                    .font(.headline)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Coins")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("🪙 \(ride.coins)")
                                    .font(.headline)
                                    .foregroundStyle(.orange)
                            }
                            
                            Spacer()
                            
                            StatusChip(status: ride.status)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    
                    // Rider Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Rider")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 50, height: 50)
                                .overlay {
                                    Text(ride.initials)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ride.name)
                                    .font(.headline)
                                Text("Posted \(ride.timeAgo)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    
                    // Actions
                    if ride.status == .posted {
                        VStack(spacing: 12) {
                            Button { openWhatsApp() } label: {
                                Label("Text on WhatsApp", systemImage: "message.fill")
                                    .font(.headline).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color.green).cornerRadius(12)
                            }

                            Button { showingBidSheet = true } label: {
                                HStack {
                                    if isLoadingBid { ProgressView().tint(.white) }
                                    Label(existingBid == nil ? "Place Bid" : "Edit Your Bid",
                                          systemImage: existingBid == nil ? "hand.raised.fill" : "pencil.circle.fill")
                                }
                                .font(.headline).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding()
                                .background(Color.black).cornerRadius(12)
                            }
                            .disabled(isLoadingBid)

                            if let bid = existingBid {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    Text("Your bid: 🪙 \(bid.bidCoins)").font(.subheadline)
                                    Spacer()
                                    Text("Waiting for rider").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    } else {
                        Button { openWhatsApp() } label: {
                            Label("Message Rider", systemImage: "message.fill")
                                .font(.headline).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding()
                                .background(Color.green).cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Ride Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingBidSheet) {
            PlaceBidSheet(ride: ride, existingBid: existingBid)
        }
        .task { await loadExistingBid() }
    }

    private func loadExistingBid() async {
        guard let uid = Auth.auth().currentUser?.uid, ride.status == .posted else { return }
        isLoadingBid = true
        let snapshot = try? await Firestore.firestore()
            .collection("rides").document(ride.id.uuidString)
            .collection("bids")
            .whereField("driverId", isEqualTo: uid)
            .whereField("status", isEqualTo: "active")
            .getDocuments()
        existingBid  = snapshot?.documents.compactMap { try? $0.data(as: RideBid.self) }.first
        isLoadingBid = false
    }

    func openWhatsApp() {
        let cleanedCountryCode = ride.whatsappCountryCode.replacingOccurrences(of: "+", with: "")
        let message = "Hi \(ride.name)! I saw your ride request on Vaahana (\(ride.from) → \(ride.to), \(ride.coins) coins). I'd love to help — interested?"
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://wa.me/\(cleanedCountryCode)\(ride.whatsappPhone)?text=\(encodedMessage)") {
            UIApplication.shared.open(url)
        }
    }

}

// Helper for corner radius on specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Distance Calculator

class DistanceCalculator {
    private let apiKey = "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImM0ZTg3Y2FjZGI5ODRhMzFhYmVmYjc2NmY1YmMwYWU1IiwiaCI6Im11cm11cjY0In0="
    
    func calculateDistance(from: String, to: String) async throws -> Double {
        // Step 1: Geocode both addresses
        let fromCoord = try await geocode(address: from)
        let toCoord = try await geocode(address: to)
        
        // Step 2: Get route distance
        let distance = try await getRouteDistance(from: fromCoord, to: toCoord)
        
        // Convert meters to miles
        return distance / 1609.34
    }
    
    func geocode(address: String) async throws -> (lat: Double, lon: Double) {
        let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // Add boundary.country parameter to bias results towards US
        let urlString = "https://api.openrouteservice.org/geocode/search?api_key=\(apiKey)&text=\(encodedAddress)&boundary.country=US"
        
        guard let url = URL(string: urlString) else {
            throw DistanceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DistanceError.invalidResponse
        }
        
        let geocodeResponse = try JSONDecoder().decode(GeocodeResponse.self, from: data)
        
        guard let firstFeature = geocodeResponse.features.first,
              firstFeature.geometry.coordinates.count >= 2 else {
            throw DistanceError.addressNotFound
        }
        
        let lon = firstFeature.geometry.coordinates[0]
        let lat = firstFeature.geometry.coordinates[1]
        
        return (lat: lat, lon: lon)
    }
    
    private func getRouteDistance(from: (lat: Double, lon: Double), to: (lat: Double, lon: Double)) async throws -> Double {
        let urlString = "https://api.openrouteservice.org/v2/directions/driving-car"
        
        guard let url = URL(string: urlString) else {
            throw DistanceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "coordinates": [
                [from.lon, from.lat],
                [to.lon, to.lat]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DistanceError.invalidResponse
        }
        
        let routeResponse = try JSONDecoder().decode(RouteResponse.self, from: data)
        
        guard let firstRoute = routeResponse.routes.first else {
            throw DistanceError.routeNotFound
        }
        
        return firstRoute.summary.distance
    }
}

enum DistanceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case addressNotFound
    case routeNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .addressNotFound:
            return "Address not found"
        case .routeNotFound:
            return "Route not found"
        }
    }
}

// API Response Models
struct GeocodeResponse: Codable {
    let features: [GeocodeFeature]
}

struct GeocodeFeature: Codable {
    let geometry: GeocodeGeometry
}

struct GeocodeGeometry: Codable {
    let coordinates: [Double]
}

struct RouteResponse: Codable {
    let routes: [Route]
}

struct Route: Codable {
    let summary: RouteSummary
}

struct RouteSummary: Codable {
    let distance: Double
}

// MARK: - Post Ride Sheet

struct PostRideSheet: View {
    @EnvironmentObject var storage: RideStorage
    @Environment(\.dismiss) var dismiss

    let editingRide: Ride?

    // Route
    @State private var pickupResult: PlaceResult? = nil
    @State private var dropoffResult: PlaceResult? = nil
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var routeETA: String? = nil
    @State private var milesText = ""
    @State private var coinsText = ""
    @State private var isCalculatingRoute = false

    // Location pickers
    @State private var showingPickupPicker = false
    @State private var showingDropoffPicker = false

    // Schedule
    @State private var hotDuration = 5
    @State private var pickupDate = Date()

    // Contact
    @State private var name = ""
    @State private var phoneCountryCode = "+1"
    @State private var phone = ""
    @State private var whatsappCountryCode = "+1"
    @State private var whatsappPhone = ""
    @State private var sameNumberForBoth = true

    @State private var isSubmitting = false

    init(editingRide: Ride? = nil) {
        self.editingRide = editingRide
    }

    let countryCodes = [
        ("🇺🇸", "+1"),
        ("🇮🇳", "+91"),
        ("🇬🇧", "+44"),
        ("🇦🇺", "+61"),
        ("🇦🇪", "+971")
    ]

    var miles: Double { Double(milesText) ?? 0 }
    var coins: Int    { Int(coinsText)    ?? 0 }
    var suggestedCoins: Int { max(1, Int(miles)) }

    var isValid: Bool {
        pickupResult != nil &&
        dropoffResult != nil &&
        miles > 0 &&
        coins > 0 &&
        !name.isEmpty &&
        phone.count >= 6 &&
        (sameNumberForBoth || whatsappPhone.count >= 6) &&
        !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Route section
                Section {
                    // Pickup row
                    Button { showingPickupPicker = true } label: {
                        LocationRow(
                            label: "Pickup",
                            systemImage: "circle.fill",
                            color: .green,
                            result: pickupResult
                        )
                    }
                    .buttonStyle(.plain)

                    // Drop-off row
                    Button { showingDropoffPicker = true } label: {
                        LocationRow(
                            label: "Drop-off",
                            systemImage: "mappin.circle.fill",
                            color: .red,
                            result: dropoffResult
                        )
                    }
                    .buttonStyle(.plain)

                    // Route preview map + stats (shown after both locations chosen)
                    if pickupResult != nil && dropoffResult != nil {
                        routePreviewCard
                    }

                    // Miles row (editable; auto-filled from route)
                    HStack {
                        TextField("0.0", text: $milesText)
                            .keyboardType(.decimalPad)
                            .onChange(of: milesText) { old, new in
                                // Only auto-update coins if user hasn't customised them
                                if coinsText.isEmpty || Int(coinsText) == max(1, Int(Double(old) ?? 0)) {
                                    if let v = Double(new) { coinsText = "\(max(1, Int(v)))" }
                                }
                            }
                        if isCalculatingRoute {
                            ProgressView().scaleEffect(0.8)
                        }
                        Text("miles").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Route")
                }

                // MARK: When
                Section {
                    DatePicker("Pickup Date & Time", selection: $pickupDate, in: Date()...)
                        .datePickerStyle(.compact)
                } header: {
                    Text("When")
                } footer: {
                    Text("Select when you need to be picked up")
                }

                // MARK: Coins
                Section {
                    HStack {
                        Text("🪙").font(.title3)
                        TextField("0", text: $coinsText)
                            .keyboardType(.numberPad)
                            .font(.title3)
                            .fontWeight(.semibold)
                        if miles > 0 && suggestedCoins != coins {
                            Button { coinsText = "\(suggestedCoins)" } label: {
                                Text("Use \(suggestedCoins)").font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Coins Offered")
                } footer: {
                    miles > 0
                        ? Text("Suggested: \(suggestedCoins) coins (1 per mile). No real money — community currency only.")
                        : Text("Coins are community currency. No real money involved.")
                }

                // MARK: Hot duration
                Section {
                    Stepper("\(hotDuration) minutes", value: $hotDuration, in: 5...60, step: 5)
                } header: {
                    Text("Keep Request Active For")
                } footer: {
                    Text("Your request disappears from drivers after this time. Default is 5 minutes.")
                }

                // MARK: Contact
                Section {
                    TextField("e.g. John Doe", text: $name).font(.body)

                    HStack(spacing: 8) {
                        Picker("Code", selection: $phoneCountryCode) {
                            ForEach(countryCodes, id: \.1) { flag, code in
                                Text("\(flag) \(code)").tag(code)
                            }
                        }
                        .labelsHidden().frame(width: 100)
                        TextField("Phone number", text: $phone).keyboardType(.numberPad)
                    }

                    Toggle(isOn: $sameNumberForBoth) {
                        Text("Same number for WhatsApp").font(.subheadline)
                    }

                    if !sameNumberForBoth {
                        HStack(spacing: 8) {
                            Picker("Code", selection: $whatsappCountryCode) {
                                ForEach(countryCodes, id: \.1) { flag, code in
                                    Text("\(flag) \(code)").tag(code)
                                }
                            }
                            .labelsHidden().frame(width: 100)
                            TextField("WhatsApp number", text: $whatsappPhone).keyboardType(.numberPad)
                        }
                    }
                } header: {
                    Text("Contact")
                } footer: {
                    Text("Drivers will reach out via WhatsApp")
                }
            }
            .navigationTitle(editingRide == nil ? "Request a Ride" : "Edit Ride Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    submitRide()
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text(editingRide == nil ? "Post Ride Request" : "Update Ride Request")
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
                .padding()
                .background(Color(UIColor.systemGroupedBackground))
            }
            .sheet(isPresented: $showingPickupPicker) {
                LocationPickerView(title: "Pickup Location") { result in
                    pickupResult = result
                    calculateRoute()
                }
            }
            .sheet(isPresented: $showingDropoffPicker) {
                LocationPickerView(title: "Drop-off Location") { result in
                    dropoffResult = result
                    calculateRoute()
                }
            }
            .onAppear { loadEditingData() }
            .task { await loadProfileDefaults() }
        }
    }

    // MARK: - Route preview card

    @ViewBuilder
    private var routePreviewCard: some View {
        VStack(spacing: 0) {
            if !routeCoords.isEmpty, let pickup = pickupResult, let dropoff = dropoffResult {
                let region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: (pickup.coordinate.latitude + dropoff.coordinate.latitude) / 2,
                        longitude: (pickup.coordinate.longitude + dropoff.coordinate.longitude) / 2
                    ),
                    span: MKCoordinateSpan(
                        latitudeDelta: abs(pickup.coordinate.latitude - dropoff.coordinate.latitude) * 1.5 + 0.01,
                        longitudeDelta: abs(pickup.coordinate.longitude - dropoff.coordinate.longitude) * 1.5 + 0.01
                    )
                )
                Map(initialPosition: .region(region)) {
                    Annotation("", coordinate: pickup.coordinate) {
                        Circle().fill(.green).frame(width: 12, height: 12)
                    }
                    Annotation("", coordinate: dropoff.coordinate) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.red).font(.title2)
                    }
                    MapPolyline(coordinates: routeCoords)
                        .stroke(.blue, lineWidth: 4)
                }
                .frame(height: 180)
                .cornerRadius(10)
                .padding(.vertical, 6)

                // Stats row
                if let eta = routeETA {
                    HStack(spacing: 20) {
                        Label(milesText + " mi", systemImage: "road.lanes")
                        Label(eta, systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                }
            } else if isCalculatingRoute {
                HStack {
                    ProgressView()
                    Text("Calculating route…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Helpers

    func loadEditingData() {
        guard let ride = editingRide else { return }
        // Restore text fields; coordinates are embedded in the ride
        milesText = String(format: "%.1f", ride.miles)
        coinsText = "\(ride.coins)"
        hotDuration = ride.hotDuration
        pickupDate = ride.pickupDate
        name = ride.name
        phoneCountryCode = ride.phoneCountryCode
        phone = ride.phone
        whatsappCountryCode = ride.whatsappCountryCode
        whatsappPhone = ride.whatsappPhone
        sameNumberForBoth = (ride.phone == ride.whatsappPhone && ride.phoneCountryCode == ride.whatsappCountryCode)

        // Restore location results from stored text (no re-geocoding needed for display)
        let pickupCoord = ride.pickupLat.flatMap { lat in
            ride.pickupLng.map { lng in CLLocationCoordinate2D(latitude: lat, longitude: lng) }
        }
        pickupResult = PlaceResult(name: ride.from, subtitle: "", coordinate: pickupCoord ?? CLLocationCoordinate2D())
        dropoffResult = PlaceResult(name: ride.to, subtitle: "", coordinate: CLLocationCoordinate2D())
    }

    func loadProfileDefaults() async {
        guard editingRide == nil,
              let uid = Auth.auth().currentUser?.uid else { return }
        guard let data = try? await Firestore.firestore()
                .collection("users").document(uid).getDocument().data() else { return }

        let savedName     = data["displayName"] as? String ?? Auth.auth().currentUser?.displayName ?? ""
        let savedPhone    = data["phone"]    as? String ?? ""
        let savedWhatsapp = data["whatsapp"] as? String ?? savedPhone

        await MainActor.run {
            if name.isEmpty          { name          = savedName }
            if phone.isEmpty         { phone          = savedPhone }
            if whatsappPhone.isEmpty { whatsappPhone  = savedWhatsapp }
        }
    }

    func submitRide() {
        let finalWhatsappPhone       = sameNumberForBoth ? phone : whatsappPhone
        let finalWhatsappCountryCode = sameNumberForBoth ? phoneCountryCode : whatsappCountryCode

        if let editingRide = editingRide {
            var updated = editingRide
            updated.name                 = name
            updated.phone                = phone
            updated.phoneCountryCode     = phoneCountryCode
            updated.whatsappPhone        = finalWhatsappPhone
            updated.whatsappCountryCode  = finalWhatsappCountryCode
            updated.from                 = pickupResult?.name ?? editingRide.from
            updated.to                   = dropoffResult?.name ?? editingRide.to
            updated.miles                = miles
            updated.coins                = coins
            updated.hotDuration          = hotDuration
            updated.pickupDate           = pickupDate
            if let coord = pickupResult?.coordinate {
                updated.pickupLat = coord.latitude
                updated.pickupLng = coord.longitude
            }
            storage.updateRide(updated)
            dismiss()
        } else {
            isSubmitting = true
            let coord = pickupResult?.coordinate
            let ride = Ride(
                riderId: Auth.auth().currentUser?.uid ?? "",
                name: name,
                phone: phone,
                phoneCountryCode: phoneCountryCode,
                whatsappPhone: finalWhatsappPhone,
                whatsappCountryCode: finalWhatsappCountryCode,
                from: pickupResult?.name ?? "",
                to: dropoffResult?.name ?? "",
                miles: miles,
                pickupLat: coord?.latitude,
                pickupLng: coord?.longitude,
                coins: coins,
                hotDuration: hotDuration,
                pickupDate: pickupDate,
                status: .posted
            )
            storage.addRide(ride)
            isSubmitting = false
            dismiss()
        }
    }

    /// Calculates route between pickup and dropoff using MKDirections.
    /// Populates routeCoords, milesText, coinsText (if not customised), and routeETA.
    func calculateRoute() {
        guard let pickup = pickupResult, let dropoff = dropoffResult else { return }
        // Skip if dropoff has no real coordinate (editing fallback placeholder)
        guard dropoff.coordinate.latitude != 0 || dropoff.coordinate.longitude != 0 else { return }
        isCalculatingRoute = true
        Task {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: pickup.coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: dropoff.coordinate))
            request.transportType = .automobile

            let response = try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<MKDirections.Response, Error>) in
                MKDirections(request: request).calculate { response, error in
                    if let response { cont.resume(returning: response) }
                    else { cont.resume(throwing: error ?? URLError(.unknown)) }
                }
            }

            await MainActor.run {
                isCalculatingRoute = false
                guard let route = response?.routes.first else { return }

                // Extract polyline coordinates
                let count = route.polyline.pointCount
                var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: count)
                route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
                routeCoords = coords

                // Distance and coins
                let calculatedMiles = route.distance / 1609.34
                let prevSuggested = max(1, Int(Double(milesText) ?? 0))
                milesText = String(format: "%.1f", calculatedMiles)
                // Only auto-update coins if user hasn't changed them from the last suggestion
                if coinsText.isEmpty || Int(coinsText) == prevSuggested {
                    coinsText = "\(max(1, Int(calculatedMiles)))"
                }

                // ETA
                let totalSeconds = Int(route.expectedTravelTime)
                let h = totalSeconds / 3600
                let m = (totalSeconds % 3600) / 60
                routeETA = h > 0 ? "\(h)h \(m)m" : "\(m) min"
            }
        }
    }
}

// MARK: - Location Row (tappable card in PostRideSheet)

private struct LocationRow: View {
    let label: String
    let systemImage: String
    let color: Color
    let result: PlaceResult?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if let result {
                    Text(result.displayTitle).font(.body).foregroundStyle(.primary)
                    if !result.displaySubtitle.isEmpty {
                        Text(result.displaySubtitle).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Tap to choose…").font(.body).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Ride Card

struct RideCard: View {
    let ride: Ride
    let isDriverMode: Bool
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onViewBids: (() -> Void)? = nil
    @EnvironmentObject var storage: RideStorage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Pickup Time at top
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text(ride.pickupDateShort)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            
            // Route
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("From")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ride.from)
                        .font(.headline)
                        .lineLimit(1)
                }
                
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("To")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ride.to)
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            
            // Chips
            HStack(spacing: 8) {
                StatusChip(status: ride.status)
                InfoChip(text: String(format: "%.1f mi", ride.miles), color: .gray)
                InfoChip(text: "🪙 \(ride.coins)", color: .orange)
            }

            // Hot timer
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = ride.hotUntil.timeIntervalSince(context.date)
                if remaining > 0 {
                    HStack(spacing: 4) {
                        Text("🔥")
                        Text(formatCountdown(remaining))
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.orange)
                        Text("left")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1)).cornerRadius(6)
                } else {
                    Label("Request expired", systemImage: "clock.badge.xmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Person
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(Color.black)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(ride.initials)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(ride.name)
                        .font(.headline)
                    Text(ride.timeAgo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Bid count button (rider mode, posted rides)
            if !isDriverMode && ride.status == .posted && ride.bidCount > 0 {
                Button { onViewBids?() } label: {
                    HStack {
                        Image(systemName: "person.2.fill")
                        Text("\(ride.bidCount) driver bid\(ride.bidCount == 1 ? "" : "s")")
                            .fontWeight(.semibold)
                        if let lowest = ride.lowestBidCoins {
                            Text("· best 🪙 \(lowest)")
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            // Actions
            if ride.status == .posted {
                if isDriverMode {
                    HStack(spacing: 12) {
                        Button {
                            openWhatsApp()
                        } label: {
                            Label("Text on WhatsApp", systemImage: "message.fill")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        
                        Button {
                            acceptRide()
                        } label: {
                            Label("Accept Ride", systemImage: "checkmark")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                } else {
                    // Rider mode - show edit/delete buttons
                    if ride.bidCount > 0 {
                        // Edit locked — drivers have placed bids
                        VStack(spacing: 6) {
                            Label("Editing locked — \(ride.bidCount) driver bid\(ride.bidCount == 1 ? "" : "s") placed", systemImage: "lock.fill")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                onDelete?()
                            } label: {
                                Label("Cancel Ride", systemImage: "xmark")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button {
                                onEdit?()
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }

                            Button {
                                onDelete?()
                            } label: {
                                Label("Cancel", systemImage: "xmark")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }
            } else {
                HStack {
                    Label("Ride confirmed", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                    
                    Spacer()
                    
                    if isDriverMode {
                        Button {
                            openWhatsApp()
                        } label: {
                            Image(systemName: "message.fill")
                                .foregroundStyle(.blue)
                        }
                    } else {
                        // Rider can still delete confirmed ride
                        Button {
                            onDelete?()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    func acceptRide() {
        var updatedRide = ride
        updatedRide.status = .accepted
        storage.updateRide(updatedRide)
    }
    
    func openWhatsApp() {
        let cleanedCountryCode = ride.whatsappCountryCode.replacingOccurrences(of: "+", with: "")
        let message = "Hi \(ride.name)! I saw your ride request on Vaahana (\(ride.from) → \(ride.to), \(ride.coins) coins). I'd love to help — interested?"
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://wa.me/\(cleanedCountryCode)\(ride.whatsappPhone)?text=\(encodedMessage)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Helpers

func formatCountdown(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Helper Views

struct StatusChip: View {
    let status: RideStatus

    var label: String {
        switch status {
        case .posted:        return "Posted"
        case .accepted:      return "Accepted"
        case .driverEnroute: return "En Route"
        case .driverArrived: return "Arrived"
        case .rideStarted:   return "In Progress"
        case .completed:     return "Completed"
        case .cancelled:     return "Cancelled"
        case .expired:       return "Expired"
        }
    }

    var icon: String {
        switch status {
        case .posted:        return "circle.fill"
        case .accepted:      return "checkmark"
        case .driverEnroute: return "car.fill"
        case .driverArrived: return "mappin.circle.fill"
        case .rideStarted:   return "play.circle.fill"
        case .completed:     return "checkmark.circle.fill"
        case .cancelled:     return "xmark.circle.fill"
        case .expired:       return "clock.badge.xmark"
        }
    }

    var color: Color {
        switch status {
        case .posted:                return .secondary
        case .accepted:              return .blue
        case .driverEnroute,
             .driverArrived:        return .orange
        case .rideStarted:           return .green
        case .completed:             return .green
        case .cancelled, .expired:   return .red
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 8))
            Text(label)
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(12)
    }
}

struct InfoChip: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    ContentView(role: .rider)
        .environmentObject(UserState())
        .environmentObject(LocationService())
}
