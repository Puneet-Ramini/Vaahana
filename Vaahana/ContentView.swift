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

    // Optional notes from rider
    var notes: String?

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
        hotDuration: Int = 30,
        pickupDate: Date,
        notes: String? = nil,
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
        self.notes = notes
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
        // Default to 1440 min (24 h) so WhatsApp rides without an explicit duration stay visible
        hotDuration            = (try? c.decodeIfPresent(Int.self, forKey: .hotDuration))              ?? 1440
        pickupDate             = (try? c.decodeIfPresent(Date.self, forKey: .pickupDate))              ?? Date()
        notes                  = try? c.decodeIfPresent(String.self, forKey: .notes)
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
    /// Posted rides visible to all riders (status == .posted), sorted newest first
    @Published var postedRides: [Ride] = []
    /// Geocoded pickup coordinates keyed by ride ID — used for distance sorting
    @Published var geocodedCoordinates: [UUID: CLLocationCoordinate2D] = [:]
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

    // MARK: - Disk cache

    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vaahana_posted_rides.json")
    }

    private func loadCachedRides() -> [Ride] {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let rides = try? JSONDecoder().decode([Ride].self, from: data) else { return [] }
        return rides
    }

    private func saveToDisk(_ rides: [Ride]) {
        guard let data = try? JSONEncoder().encode(rides) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    // MARK: - Geocoding

    /// Geocode pickup locations in the background for rides that don't have stored coords.
    /// Results are stored in `geocodedCoordinates` so RiderView and MapTabView can use them.
    func geocodeRides(_ rides: [Ride]) {
        Task {
            for ride in rides {
                guard geocodedCoordinates[ride.id] == nil else { continue }
                let coord: CLLocationCoordinate2D?
                if let lat = ride.pickupLat, let lng = ride.pickupLng {
                    coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                } else {
                    let req = MKLocalSearch.Request()
                    req.naturalLanguageQuery = ride.from
                    req.resultTypes = .address
                    coord = try? await MKLocalSearch(request: req).start().mapItems.first?.placemark.coordinate
                }
                if let c = coord {
                    await MainActor.run { self.geocodedCoordinates[ride.id] = c }
                }
            }
        }
    }

    init(role: UserRole) {
        self.role = role
        self.uid = Auth.auth().currentUser?.uid ?? ""
        // Show cached rides instantly before the first network snapshot arrives
        let cached = loadCachedRides()
        if !cached.isEmpty {
            self.postedRides = cached
            self.isLoading = false
            geocodeRides(cached)
        }
        startListening()
    }

    deinit {
        listeners.forEach { $0.remove() }
    }

    private func startListening() {
        if role == .rider {
            // Rider: own rides (for managing their own requests)
            let l = db.collection("rides")
                .whereField("riderId", isEqualTo: uid)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self, let snapshot else { return }
                    let rides = snapshot.documents.compactMap { try? $0.data(as: Ride.self) }
                    self.myRides = rides.sorted { $0.createdAt > $1.createdAt }
                    self.activeRide = rides.first { $0.status.isActive }

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

            // Rider: all posted rides from community feed (WhatsApp + app)
            let l2 = db.collection("rides")
                .whereField("status", isEqualTo: "posted")
                .addSnapshotListener { [weak self] snapshot, error in
                    guard let self else { return }
                    if let error {
                        print("[RideStorage] feed snapshot error: \(error)")
                        self.isLoading = false  // don't spin forever on error
                        return
                    }
                    guard let snapshot else { return }
                    var decoded: [Ride] = []
                    for doc in snapshot.documents {
                        do {
                            let ride = try doc.data(as: Ride.self)
                            decoded.append(ride)
                        } catch {
                            print("[RideStorage] decode failed docID=\(doc.documentID) error=\(error)")
                        }
                    }
                    // Don't wipe existing data with an empty cached snapshot —
                    // wait for real server data before clearing the list
                    if !decoded.isEmpty || !snapshot.metadata.isFromCache {
                        let sorted = self.deduplicatePostedRides(decoded)
                            .sorted { $0.createdAt > $1.createdAt }
                        self.postedRides = sorted
                        self.isLoading = false
                        self.saveToDisk(sorted)
                        self.geocodeRides(sorted)
                        self.backfillMissingMilesIfNeeded(in: sorted)
                    }
                }
            listeners.append(l2)
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
                    if !decoded.isEmpty || !snapshot.metadata.isFromCache {
                        let sorted = self.deduplicatePostedRides(decoded)
                            .sorted { $0.createdAt > $1.createdAt }
                        self.postedRides = sorted
                        self.isLoading = false
                        self.saveToDisk(sorted)
                        self.geocodeRides(sorted)
                        self.backfillMissingMilesIfNeeded(in: sorted)
                    }
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

// MARK: - Tab Selection

enum MainTab: String, CaseIterable {
    case rides = "Rides"
    case map = "Map"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .rides:    return "car.side.fill"
        case .map:      return "map"
        case .settings: return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .rides:    return "car.side.fill"
        case .map:      return "map.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    let role: UserRole
    @StateObject private var storage: RideStorage
    @EnvironmentObject var userState: UserState
    @EnvironmentObject var locationService: LocationService
    @State private var selectedTab: MainTab = .rides
    @State private var showingAdmin = false

    init(role: UserRole) {
        self.role = role
        _storage = StateObject(wrappedValue: RideStorage(role: role))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Header — hidden on map tab for full-screen experience
                if selectedTab != .map {
                    header
                }

                // Tab content
                Group {
                    switch selectedTab {
                    case .rides:
                        RiderView()
                    case .map:
                        MapTabView(role: .rider)
                    case .settings:
                        SettingsTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Floating tab bar
            floatingTabBar
                .padding(.horizontal, 16)
                .padding(.bottom, -10)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .environmentObject(storage)
        .sheet(isPresented: $showingAdmin) {
            AdminView()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Image("Vaahana Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 36)
            Spacer()
            if userState.isAdmin {
                Button { showingAdmin = true } label: {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 36, height: 36)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Floating Tab Bar (Sixt-style)

    private var visibleTabs: [MainTab] {
        return MainTab.allCases
    }

    private var floatingTabBar: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 20, weight: .medium))
                            .symbolRenderingMode(.monochrome)
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    }
                    .foregroundStyle(isSelected ? Color.red : Color(UIColor.label))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.white.opacity(0.6))
                            }
                        }
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassEffect(in: .capsule)
    }
}

// MARK: - Rider View

struct RiderView: View {
    @EnvironmentObject var storage: RideStorage
    @EnvironmentObject var locationService: LocationService
    @State private var showingPostSheet = false
    @State private var selectedRide: Ride?
    @State private var showMyRequests = false
    @State private var showExpiredRequests = false
    @State private var searchText = ""

    var myActiveRides: [Ride] {
        storage.myRides.filter { $0.status == .posted }
    }

    var myExpiredRides: [Ride] {
        storage.myRides.filter { $0.status == .expired || $0.status == .cancelled }
    }

    /// Rides filtered by search and sorted: nearest pickup first, then newest within same distance bucket.
    var displayedRides: [Ride] {
        let base: [Ride] = searchText.isEmpty
            ? storage.postedRides
            : storage.postedRides.filter { $0.from.localizedCaseInsensitiveContains(searchText) }

        guard let userLoc = locationService.location else {
            // No location yet — just newest first
            return base
        }
        let userCL = CLLocation(latitude: userLoc.coordinate.latitude, longitude: userLoc.coordinate.longitude)

        return base.sorted { a, b in
            let aC = storage.geocodedCoordinates[a.id]
            let bC = storage.geocodedCoordinates[b.id]
            if let aC, let bC {
                let aDist = CLLocation(latitude: aC.latitude, longitude: aC.longitude).distance(from: userCL)
                let bDist = CLLocation(latitude: bC.latitude, longitude: bC.longitude).distance(from: userCL)
                // If more than 1 mile apart, closer ride wins
                if abs(aDist - bDist) > 1609 { return aDist < bDist }
            }
            // Same distance bucket (or no coords) → newest first
            return a.createdAt > b.createdAt
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if storage.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        // Section header
                        HStack(alignment: .firstTextBaseline) {
                            Text("Available Rides")
                                .font(.title3).fontWeight(.bold)
                            Text("\(displayedRides.count)")
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 4)

                        // Search bar
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 14))
                            TextField("Search by pickup location...", text: $searchText)
                                .font(.subheadline)
                                .autocorrectionDisabled()
                            if !searchText.isEmpty {
                                Button { searchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        // Community feed: sorted & filtered rides
                        if displayedRides.isEmpty {
                            emptyState
                        } else {
                            ForEach(displayedRides) { ride in
                                CompactRideRow(ride: ride) {
                                    selectedRide = ride
                                }
                            }
                        }

                        // My Active Requests — collapsible
                        if !myActiveRides.isEmpty {
                            collapsibleSection(
                                title: "My Requests",
                                count: myActiveRides.count,
                                isExpanded: $showMyRequests,
                                accentColor: .blue
                            ) {
                                ForEach(myActiveRides) { ride in
                                    CompactRideRow(ride: ride) { selectedRide = ride }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { storage.deleteRide(ride) } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }

                        // Expired Requests — collapsible, muted
                        if !myExpiredRides.isEmpty {
                            collapsibleSection(
                                title: "Expired",
                                count: myExpiredRides.count,
                                isExpanded: $showExpiredRequests,
                                accentColor: .secondary
                            ) {
                                ForEach(myExpiredRides) { ride in
                                    CompactRideRow(ride: ride) { selectedRide = ride }
                                        .opacity(0.55)
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { storage.deleteRide(ride) } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .overlay(alignment: .bottom) {
            Button {
                showingPostSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                    Text("Post a Ride Request")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 84)
        }
        .sheet(isPresented: $showingPostSheet) { PostRideSheet() }
        .sheet(item: $selectedRide) { ride in RideDetailSheet(ride: ride) }
    }

    @ViewBuilder
    private func collapsibleSection<Content: View>(
        title: String,
        count: Int,
        isExpanded: Binding<Bool>,
        accentColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { isExpanded.wrappedValue.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(accentColor)
                    Text("\(count)")
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(accentColor.opacity(0.6))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No rides available")
                .font(.headline)
            Text("Check back soon — rides from the\nWhatsApp group appear here.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Driver Feed Tab

private enum DriverFeedTab: String, CaseIterable, Identifiable {
    case all = "All"
    case whatsApp = "WhatsApp"

    var id: String { rawValue }
}

// MARK: - Driver View (List-only)

struct DriverView: View {
    @EnvironmentObject var storage: RideStorage
    @EnvironmentObject private var locationService: LocationService
    @State private var selectedRide: Ride?
    @State private var showingActiveRide = false
    @State private var showingMyBids = false
    @State private var ratingRide: Ride?

    @AppStorage("filterRadius") private var filterRadius = 5.0
    @AppStorage("driverCenterLat") private var driverCenterLat: Double = 0
    @AppStorage("driverCenterLon") private var driverCenterLon: Double = 0
    @AppStorage("driverCenterCustom") private var driverCenterCustom: Bool = false

    private var mapCenter: CLLocationCoordinate2D? {
        if driverCenterCustom {
            return CLLocationCoordinate2D(latitude: driverCenterLat, longitude: driverCenterLon)
        }
        return locationService.location?.coordinate
    }

    private static let listRadiusMiles = 100.0

    var filteredRides: [(ride: Ride, distanceMiles: Double?)] {
        let hot = storage.hotPostedRides
        guard let userLoc = locationService.location else {
            // No location yet — show all rides unsorted
            return hot.map { ($0, nil) }
        }
        return hot
            .compactMap { ride -> (ride: Ride, distanceMiles: Double?)? in
                guard let lat = ride.pickupLat, let lng = ride.pickupLng else {
                    // No coords — include but distance unknown
                    return (ride, nil)
                }
                let dist = userLoc.distance(from: CLLocation(latitude: lat, longitude: lng)) / 1609.34
                guard dist <= Self.listRadiusMiles else { return nil }
                return (ride, dist)
            }
            .sorted {
                switch ($0.distanceMiles, $1.distanceMiles) {
                case let (a?, b?): return a < b
                case (_?, nil):    return true
                case (nil, _?):    return false
                default:           return $0.ride.hotUntil > $1.ride.hotUntil
                }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content
            if storage.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        // Active ride banner
                        if let active = storage.activeRide {
                            Button { showingActiveRide = true } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.blue.opacity(0.12)).frame(width: 44, height: 44)
                                        Image(systemName: "car.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(.blue)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Active Ride").font(.caption).foregroundStyle(.secondary)
                                        Text(active.status.driverDisplayText)
                                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(.blue)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(14)
                                .background(Color.blue.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.blue.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                        }

                        // My Bids
                        Button { showingMyBids = true } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color.purple.opacity(0.12)).frame(width: 44, height: 44)
                                    Image(systemName: "list.bullet.rectangle.portrait")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.purple)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("My Bids").font(.subheadline).fontWeight(.semibold)
                                    Text("Track bids you've placed").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        // Section header
                        HStack(alignment: .firstTextBaseline) {
                            Text("Hot Requests")
                                .font(.title3).fontWeight(.bold)
                            Text("\(filteredRides.count)")
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 4)

                        // Rides
                        if filteredRides.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: storage.hotPostedRides.isEmpty ? "car.2.fill" : "location.slash")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.quaternary)
                                Text(storage.hotPostedRides.isEmpty
                                     ? "No requests right now"
                                     : "No requests within \(Int(DriverView.listRadiusMiles)) mi")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                        } else {
                            ForEach(filteredRides, id: \.ride.id) { item in
                                CompactRideRow(ride: item.ride, distanceMiles: item.distanceMiles) {
                                    selectedRide = item.ride
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)  // More space for floating tab bar
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .sheet(item: $selectedRide) { ride in RideDetailSheet(ride: ride) }
        .sheet(isPresented: $showingActiveRide) {
            if let active = storage.activeRide {
                ActiveRideView(ride: active, role: .driver)
            }
        }
        .sheet(isPresented: $showingMyBids) { DriverBidsView() }
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
                    VStack(spacing: 2) {
                        Text(dist < 0.1 ? "<0.1" : String(format: dist < 10 ? "%.1f" : "%.0f", dist))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("mi")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(dist < 2 ? .green : dist < 10 ? .orange : .secondary)
                    .frame(width: 40, height: 40)
                    .background((dist < 2 ? Color.green : dist < 10 ? Color.orange : Color.secondary).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                // Content
                VStack(alignment: .leading, spacing: 5) {
                    // Route
                    HStack(spacing: 5) {
                        Text(ride.from)
                            .font(.subheadline).fontWeight(.semibold)
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Text(ride.to)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Meta row
                    HStack(spacing: 6) {
                        Label(ride.pickupDateShort, systemImage: "calendar")
                            .font(.caption).foregroundStyle(.secondary)

                        if ride.miles > 0 {
                            Text("·").foregroundStyle(.quaternary)
                            Text(String(format: "%.1f mi", ride.miles))
                                .font(.caption).foregroundStyle(.secondary)
                        }

                        Text("·").foregroundStyle(.quaternary)
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text(ride.createdAt, format: .dateTime.hour().minute())
                            .font(.caption).foregroundStyle(.orange)
                    }

                    // Tags row
                    HStack(spacing: 6) {
                        if ride.isWhatsAppSource {
                            Text("WhatsApp")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6).padding(.vertical, 2.5)
                                .background(Color.green.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        Text("🪙 \(ride.coins)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)

                        Spacer()

                        TimelineView(.periodic(from: .now, by: 60)) { ctx in
                            let rem = ride.hotUntil.timeIntervalSince(ctx.date)
                            if rem > 0 {
                                let mins = Int(rem / 60)
                                Text(mins >= 60 ? "\(mins / 60)h" : "\(max(1, mins))m")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.orange)
                            } else {
                                Text("Expired")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(12)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ride Detail Map Pin model

private struct RideMapPin: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let isPickup: Bool
    let label: String
}

// MARK: - Ride Detail Sheet

struct RideDetailSheet: View {
    let ride: Ride
    @Environment(\.dismiss) var dismiss

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var mapPins: [RideMapPin] = []
    @State private var routeMinutes: Int? = nil
    @State private var routeDistanceMiles: Double? = nil
    @State private var isCalculatingRoute = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: Map — pickup (green) + drop-off (red) once geocoded
                    Map(position: $mapPosition) {
                        ForEach(mapPins) { pin in
                            Annotation(pin.label, coordinate: pin.coordinate) {
                                ZStack {
                                    Circle()
                                        .fill(pin.isPickup ? Color.green : Color.red)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: pin.isPickup ? "circle.fill" : "mappin")
                                        .font(.system(size: pin.isPickup ? 12 : 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .shadow(color: .black.opacity(0.25), radius: 4)
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Button { openAppleMaps() } label: {
                            Label("Open in Maps", systemImage: "arrow.up.right.square")
                                .font(.caption2).fontWeight(.medium)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .padding(10)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if isCalculatingRoute {
                            ProgressView()
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .padding(10)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    VStack(spacing: 12) {
                        // MARK: Route card
                        VStack(spacing: 14) {
                            HStack(spacing: 12) {
                                VStack(spacing: 6) {
                                    Circle().fill(.green).frame(width: 10, height: 10)
                                    Rectangle().fill(Color(UIColor.separator)).frame(width: 1.5, height: 22)
                                    Image(systemName: "mappin.circle.fill").font(.system(size: 14)).foregroundStyle(.red)
                                }
                                VStack(alignment: .leading, spacing: 14) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Pickup").font(.caption).foregroundStyle(.secondary)
                                        Text(ride.from).font(.subheadline).fontWeight(.semibold)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Drop-off").font(.caption).foregroundStyle(.secondary)
                                        Text(ride.to).font(.subheadline).fontWeight(.semibold)
                                    }
                                }
                                Spacer()
                            }

                            Divider()

                            // Stats row
                            HStack(spacing: 0) {
                                detailStat(icon: "calendar", label: "Pickup", value: ride.pickupDateShort)
                                Divider().frame(height: 34)
                                detailStat(
                                    icon: "road.lanes",
                                    label: "Distance",
                                    value: routeDistanceMiles.map { String(format: "%.1f mi", $0) }
                                        ?? (ride.miles > 0 ? String(format: "%.1f mi", ride.miles) : "—")
                                )
                                Divider().frame(height: 34)
                                detailStat(
                                    icon: "clock",
                                    label: "Drive time",
                                    value: routeMinutes.map { formatMinutes($0) } ?? "—"
                                )
                            }
                        }
                        .padding(14)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // MARK: Requester + time since posted
                        HStack(spacing: 14) {
                            Circle()
                                .fill(Color.blue.gradient)
                                .frame(width: 48, height: 48)
                                .overlay {
                                    Text(ride.initials)
                                        .font(.subheadline).fontWeight(.bold)
                                        .foregroundStyle(.white)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(ride.name.isEmpty ? "Unknown" : ride.name)
                                    .font(.headline)
                                HStack(spacing: 6) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.orange)
                                    Text("Posted \(ride.timeAgo)")
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundStyle(.orange)
                                }
                                if ride.isWhatsAppSource {
                                    Text("via WhatsApp")
                                        .font(.caption).foregroundStyle(.green)
                                }
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // MARK: Notes
                        if let notes = ride.notes, !notes.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "text.bubble.fill")
                                    .font(.system(size: 14)).foregroundStyle(.blue).padding(.top, 2)
                                Text(notes).font(.subheadline).foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(14)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        // MARK: WhatsApp CTA
                        Button { openWhatsApp() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "message.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Message on WhatsApp")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(red: 0.07, green: 0.69, blue: 0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Ride Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadRouteInfo() }
    }

    // MARK: - Route loading

    /// Geocode a natural-language place name using MKLocalSearch (handles bare city names better than CLGeocoder)
    private func geocodePlace(_ query: String) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        return response.mapItems.first?.placemark.coordinate
    }

    private func loadRouteInfo() async {
        await MainActor.run { isCalculatingRoute = true }

        // Resolve pickup coordinate — use stored coords if available, else geocode ride.from
        let pickupCoord: CLLocationCoordinate2D?
        if let lat = ride.pickupLat, let lng = ride.pickupLng {
            pickupCoord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else {
            pickupCoord = await geocodePlace(ride.from)
        }

        // Geocode destination
        let destCoord = await geocodePlace(ride.to)

        await MainActor.run {
            var pins: [RideMapPin] = []
            if let p = pickupCoord {
                pins.append(RideMapPin(id: "pickup", coordinate: p, isPickup: true, label: ride.from))
            }
            if let d = destCoord {
                pins.append(RideMapPin(id: "dest", coordinate: d, isPickup: false, label: ride.to))
            }
            mapPins = pins

            // Fit camera to show all pins
            if let p = pickupCoord, let d = destCoord {
                let minLat = min(p.latitude, d.latitude)
                let maxLat = max(p.latitude, d.latitude)
                let minLng = min(p.longitude, d.longitude)
                let maxLng = max(p.longitude, d.longitude)
                let latDelta = max(0.04, (maxLat - minLat) * 1.5)
                let lngDelta = max(0.04, (maxLng - minLng) * 1.5)
                mapPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: (minLat + maxLat) / 2,
                        longitude: (minLng + maxLng) / 2
                    ),
                    span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
                ))
            } else if let p = pickupCoord {
                mapPosition = .region(MKCoordinateRegion(
                    center: p,
                    span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
                ))
            } else if let d = destCoord {
                mapPosition = .region(MKCoordinateRegion(
                    center: d,
                    span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
                ))
            }
        }

        // Calculate driving route if we have both coordinates
        if let p = pickupCoord, let d = destCoord {
            let request = MKDirections.Request()
            request.source      = MKMapItem(placemark: MKPlacemark(coordinate: p))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: d))
            request.transportType = .automobile
            if let response = try? await MKDirections(request: request).calculate(),
               let route = response.routes.first {
                await MainActor.run {
                    routeDistanceMiles = route.distance / 1609.34
                    routeMinutes = Int(route.expectedTravelTime / 60)
                }
            }
        }

        await MainActor.run { isCalculatingRoute = false }
    }

    // MARK: - Helpers

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func detailStat(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15)).foregroundStyle(.blue)
            Text(value)
                .font(.subheadline).fontWeight(.semibold)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func openWhatsApp() {
        // Strip everything except digits from both fields
        let codeDigits = ride.whatsappCountryCode
            .components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        let phoneDigits = ride.whatsappPhone
            .components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        // whatsappPhone often already contains the full number (e.g. +16176206435)
        // so avoid prepending the country code if it's already present
        let fullNumber = phoneDigits.hasPrefix(codeDigits) ? phoneDigits : codeDigits + phoneDigits
        let message = "Hi \(ride.name)! I saw your ride request (\(ride.from) → \(ride.to)) on Vaahana. Are you still looking for a ride?"
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://wa.me/\(fullNumber)?text=\(encodedMessage)") {
            UIApplication.shared.open(url)
        }
    }

    private func openAppleMaps() {
        guard let pin = mapPins.first(where: { $0.isPickup }) else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
        item.name = ride.from
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
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
    @State private var hotDuration = 30
    @State private var pickupDate = Date()

    // Notes
    @State private var notes = ""

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
                    Button { showingPickupPicker = true } label: {
                        LocationRow(
                            label: "Pickup",
                            systemImage: "circle.fill",
                            color: .green,
                            result: pickupResult
                        )
                    }
                    .buttonStyle(.plain)

                    Button { showingDropoffPicker = true } label: {
                        LocationRow(
                            label: "Drop-off",
                            systemImage: "mappin.circle.fill",
                            color: .red,
                            result: dropoffResult
                        )
                    }
                    .buttonStyle(.plain)

                    if pickupResult != nil && dropoffResult != nil {
                        routePreviewCard
                    }
                } header: {
                    Label("Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                }

                // MARK: Details
                Section {
                    HStack {
                        Label("Distance", systemImage: "road.lanes")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        TextField("0.0", text: $milesText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .onChange(of: milesText) { old, new in
                                if coinsText.isEmpty || Int(coinsText) == max(1, Int(Double(old) ?? 0)) {
                                    if let v = Double(new) { coinsText = "\(max(1, Int(v)))" }
                                }
                            }
                        Text("mi").foregroundStyle(.secondary).font(.subheadline)
                        if isCalculatingRoute { ProgressView().scaleEffect(0.7) }
                    }

                    HStack {
                        Label("Coins", systemImage: "centsign.circle.fill")
                            .font(.subheadline).foregroundStyle(.orange)
                        Spacer()
                        TextField("0", text: $coinsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .fontWeight(.semibold)
                        if miles > 0 && suggestedCoins != coins {
                            Button { coinsText = "\(suggestedCoins)" } label: {
                                Text("Suggest \(suggestedCoins)")
                                    .font(.caption2).fontWeight(.medium)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    DatePicker("Pickup", selection: $pickupDate, in: Date()...)
                        .datePickerStyle(.compact)

                    Picker("Active for", selection: $hotDuration) {
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                        Text("5 hours").tag(300)
                        Text("1 day").tag(1440)
                    }
                } header: {
                    Label("Details", systemImage: "slider.horizontal.3")
                } footer: {
                    Text("Coins are community currency — no real money. Request expires after the active duration.")
                }

                // MARK: Notes
                Section {
                    TextField("Special instructions for the driver…", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Label("Notes", systemImage: "text.bubble")
                }

                // MARK: Contact
                Section {
                    HStack {
                        Label("Name", systemImage: "person.fill")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .leading)
                        TextField("Full Name", text: $name)
                            .multilineTextAlignment(.trailing)
                    }

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
                        Text("Same for WhatsApp").font(.subheadline)
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
                    Label("Contact", systemImage: "phone.fill")
                } footer: {
                    Text("Drivers will reach out via WhatsApp")
                }
            }
            .navigationTitle(editingRide == nil ? "Request a Ride" : "Edit Request")
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
                            Label(
                                editingRide == nil ? "Post Request" : "Update Request",
                                systemImage: editingRide == nil ? "paperplane.fill" : "checkmark"
                            )
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isValid ? Color.blue : Color.gray.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!isValid)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(.bar)
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
        notes = ride.notes ?? ""
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
            updated.notes                = notes.isEmpty ? nil : notes
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
                notes: notes.isEmpty ? nil : notes,
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

// MARK: - Map Tab View

private struct MapRidePin: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let ride: Ride
}

struct MapTabView: View {
    let role: UserRole
    @EnvironmentObject var storage: RideStorage
    @EnvironmentObject var locationService: LocationService
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedRide: Ride?
    @State private var mapRidePins: [MapRidePin] = []
    @State private var hasCenteredOnUser = false
    @State private var showLocationDeniedAlert = false

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                // Live location
                if let loc = locationService.location {
                    Annotation("Me", coordinate: loc.coordinate) {
                        ZStack {
                            Circle().fill(Color.blue.opacity(0.2)).frame(width: 40, height: 40)
                            Circle().fill(Color.blue).frame(width: 14, height: 14)
                            Circle().stroke(Color.white, lineWidth: 2.5).frame(width: 14, height: 14)
                        }
                        .shadow(color: .blue.opacity(0.35), radius: 8)
                    }
                }

                // Ride pins — geocoded pickup locations
                ForEach(mapRidePins) { pin in
                    Annotation(pin.ride.from, coordinate: pin.coordinate) {
                        mapPin(for: pin.ride)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
            }

            // Re-center button
            VStack {
                HStack {
                    Spacer()
                    Button { handleRecenterTap() } label: {
                        Image(systemName: locationIconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(locationIconColor)
                            .frame(width: 40, height: 40)
                            .background(.ultraThickMaterial)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.1), radius: 4)
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()

                // Bottom count card
                let total = storage.postedRides.count
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.red)
                    Text("\(total) ride\(total == 1 ? "" : "s") available")
                        .font(.caption).fontWeight(.semibold)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(in: .rect(cornerRadius: 14))
                .padding(.horizontal, 16)
                .padding(.bottom, 72)
            }
        }
        .onAppear {
            locationService.startUpdatingIfAuthorized()
            if locationService.location != nil { recenterMap() }
            rebuildMapPins()
        }
        .onChange(of: locationService.location) { _, newLoc in
            guard !hasCenteredOnUser, newLoc != nil else { return }
            hasCenteredOnUser = true
            recenterMap()
        }
        .onChange(of: storage.geocodedCoordinates.count) { _, _ in
            rebuildMapPins()
        }
        .sheet(item: $selectedRide) { ride in RideDetailSheet(ride: ride) }
        .alert("Location Access Required", isPresented: $showLocationDeniedAlert) {
            Button("Open Settings") { locationService.openAppSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable location access in Settings so the map can center on your position.")
        }
    }

    private var locationIconName: String {
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "location.fill"
        case .denied, .restricted:
            return "location.slash.fill"
        default:
            return "location"
        }
    }

    private var locationIconColor: Color {
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .blue
        case .denied, .restricted:
            return .red
        default:
            return .secondary
        }
    }

    private func handleRecenterTap() {
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationService.startUpdatingIfAuthorized()
            recenterMap()
        case .denied, .restricted:
            showLocationDeniedAlert = true
        case .notDetermined:
            locationService.startUpdatingIfAuthorized()
        @unknown default:
            break
        }
    }

    /// Build map pins from the already-geocoded coordinates in RideStorage (no duplicate geocoding).
    private func rebuildMapPins() {
        mapRidePins = storage.postedRides.compactMap { ride in
            guard let coord = storage.geocodedCoordinates[ride.id] else { return nil }
            return MapRidePin(id: ride.id.uuidString, coordinate: coord, ride: ride)
        }
    }

    private func recenterMap() {
        if let loc = locationService.location {
            withAnimation(.spring(response: 0.3)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    latitudinalMeters: 8000,
                    longitudinalMeters: 8000
                ))
            }
        }
    }

    // MARK: - Map Pin

    private func mapPin(for ride: Ride) -> some View {
        let heat = max(0, min(1, ride.hotUntil.timeIntervalSinceNow / Double(ride.hotDuration * 60)))
        let pinColor = Color(
            hue: Double(0.08 - 0.08 * (1 - heat)),
            saturation: 0.9,
            brightness: 0.5 + 0.5 * heat
        )
        let size: CGFloat = 34 + 10 * heat

        return Button { selectedRide = ride } label: {
            ZStack {
                Circle()
                    .fill(pinColor)
                    .frame(width: size, height: size)
                    .shadow(color: pinColor.opacity(heat > 0.6 ? 0.6 : 0.15), radius: heat > 0.6 ? 8 : 3)
                VStack(spacing: 1) {
                    Image(systemName: "figure.wave")
                        .font(.system(size: size * 0.28)).foregroundStyle(.white)
                    if ride.coins > 0 {
                        Text("🪙\(ride.coins)")
                            .font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                    }
                }
                if ride.isWhatsAppSource {
                    VStack {
                        HStack {
                            Spacer()
                            Text("WA")
                                .font(.system(size: 6, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1.5)
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

// MARK: - Switch Role Tab

struct SwitchRoleTab: View {
    @EnvironmentObject var userState: UserState
    @State private var isSwitching = false
    @State private var errorMessage: String?

    private let db = Firestore.firestore()

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer().frame(height: 24)

                // Current role badge
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(userState.role == .driver
                                  ? Color.black.opacity(0.08)
                                  : Color.blue.opacity(0.1))
                            .frame(width: 100, height: 100)
                        Image(systemName: userState.role == .driver ? "car.fill" : "figure.wave")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(userState.role == .driver ? Color.primary : Color.blue)
                    }

                    VStack(spacing: 4) {
                        Text("Currently")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(userState.role == .driver ? "Driver" : "Rider")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }
                }

                // Role options
                VStack(spacing: 12) {
                    roleOption(
                        icon: "figure.wave",
                        title: "Rider",
                        description: "Post ride requests and let drivers bid to help you.",
                        isActive: userState.role == .rider,
                        color: .blue,
                        onSelect: { switchRole(to: .rider) }
                    )
                    roleOption(
                        icon: "car.fill",
                        title: "Driver",
                        description: "Browse nearby requests, place bids, and earn coins.",
                        isActive: userState.role == .driver,
                        color: .primary,
                        onSelect: { switchRole(to: .driver) }
                    )
                }
                .padding(.horizontal, 20)

                if isSwitching {
                    ProgressView()
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func roleOption(icon: String, title: String, description: String, isActive: Bool, color: Color, onSelect: @escaping () -> Void) -> some View {
        Button(action: { if !isActive { onSelect() } }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isActive ? .white : color)
                    .frame(width: 44, height: 44)
                    .background(isActive ? Color.blue : Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.body).fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        if isActive {
                            Text("Active")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.green)
                                .clipShape(Capsule())
                        }
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isActive ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSwitching)
    }

    private func switchRole(to newRole: UserRole) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSwitching = true
        errorMessage = nil
        Task {
            do {
                try await db.collection("users").document(uid).setData(["role": newRole.rawValue], merge: true)
                await MainActor.run {
                    userState.role = newRole
                    isSwitching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSwitching = false
                }
            }
        }
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    @EnvironmentObject var userState: UserState
    @State private var displayName = ""
    @State private var phone = ""
    @State private var whatsapp = ""
    @State private var coins: Int = 0
    @State private var ratingAverage: Double? = nil
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Driver vehicle info
    @State private var vehicleMake  = ""
    @State private var vehicleModel = ""
    @State private var vehicleColor = ""
    @State private var vehiclePlate = ""

    @State private var showingHistory = false
    @State private var showingSaveConfirmation = false
    @State private var isOnline = true

    private var currentUser: FirebaseAuth.User? { Auth.auth().currentUser }
    private let db = Firestore.firestore()

    private var initials: String {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            return String(currentUser?.email?.prefix(2) ?? "?").uppercased()
        }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    private var hasChanges: Bool {
        // Compare with initial values loaded from Firestore
        return !isSaving
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Profile Header
                Section {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.blue.gradient)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Text(initials)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(displayName.isEmpty ? "User" : displayName)
                                .font(.headline)
                            Text(currentUser?.email ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Label(userState.role == .driver ? "Driver" : "Rider",
                                      systemImage: userState.role == .driver ? "car.fill" : "figure.wave")
                                    .font(.caption).foregroundStyle(.blue)
                                Label("🪙 \(coins)", systemImage: "")
                                    .font(.caption).fontWeight(.semibold).foregroundStyle(.orange)
                                if let avg = ratingAverage {
                                    HStack(spacing: 2) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 10)).foregroundStyle(.yellow)
                                        Text(String(format: "%.1f", avg))
                                            .font(.caption).fontWeight(.semibold)
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }
                        Spacer()
                    }
                }
                
                // MARK: - Personal Information
                Section {
                    HStack {
                        Label("Name", systemImage: "person.fill")
                            .frame(width: 100, alignment: .leading)
                        TextField("Full Name", text: $displayName)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Label("Phone", systemImage: "phone.fill")
                            .frame(width: 100, alignment: .leading)
                        TextField("Phone Number", text: $phone)
                            .keyboardType(.phonePad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Label("WhatsApp", systemImage: "message.fill")
                            .frame(width: 100, alignment: .leading)
                        TextField("WhatsApp Number", text: $whatsapp)
                            .keyboardType(.phonePad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Personal Information")
                } footer: {
                    Text("These details will be used to auto-fill ride requests")
                }
                
                // MARK: - Online Status (Driver only)
                if userState.role == .driver {
                    Section {
                        Toggle(isOn: $isOnline) {
                            Label {
                                Text(isOnline ? "Online" : "Offline")
                            } icon: {
                                Circle()
                                    .fill(isOnline ? Color.green : Color(UIColor.tertiaryLabel))
                                    .frame(width: 10, height: 10)
                            }
                        }
                        .tint(.green)
                        .onChange(of: isOnline) { _, online in
                            guard let uid = Auth.auth().currentUser?.uid else { return }
                            Firestore.firestore().collection("users").document(uid)
                                .setData(["isAvailable": online], merge: true)
                        }
                    } header: {
                        Text("Availability")
                    } footer: {
                        Text("When offline, you won't see new ride requests")
                    }
                }

                // MARK: - Vehicle Information (Driver only)
                if userState.role == .driver {
                    Section {
                        HStack {
                            Label("Make", systemImage: "car.fill")
                                .frame(width: 100, alignment: .leading)
                            TextField("e.g. Toyota", text: $vehicleMake)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        HStack {
                            Label("Model", systemImage: "car.fill")
                                .frame(width: 100, alignment: .leading)
                            TextField("e.g. Camry", text: $vehicleModel)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        HStack {
                            Label("Color", systemImage: "paintpalette.fill")
                                .frame(width: 100, alignment: .leading)
                            TextField("Vehicle Color", text: $vehicleColor)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        HStack {
                            Label("Plate", systemImage: "number.circle.fill")
                                .frame(width: 100, alignment: .leading)
                            TextField("License Plate", text: $vehiclePlate)
                                .autocapitalization(.allCharacters)
                                .multilineTextAlignment(.trailing)
                        }
                    } header: {
                        Text("Vehicle Information")
                    } footer: {
                        Text("Shown to riders when you accept a ride")
                    }
                }
                
                // MARK: - History
                Section {
                    NavigationLink {
                        RideHistoryView(role: userState.role ?? .rider)
                    } label: {
                        Label("Ride History", systemImage: "clock.arrow.circlepath")
                    }
                } header: {
                    Text("Activity")
                }
                
                // MARK: - Error Message
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                
                // MARK: - Save Button
                Section {
                    Button {
                        save()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Save Changes")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSaving)
                }
                
                // MARK: - Sign Out
                Section {
                    Button(role: .destructive) {
                        try? Auth.auth().signOut()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                            Spacer()
                        }
                    }
                }
            }
            .contentMargins(.bottom, 80)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Changes Saved", isPresented: $showingSaveConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your profile has been updated successfully")
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let uid = currentUser?.uid else { return }
        if let data = try? await db.collection("users").document(uid).getDocument().data() {
            await MainActor.run {
                displayName  = data["displayName"] as? String ?? currentUser?.displayName ?? ""
                phone        = data["phone"]       as? String ?? ""
                whatsapp     = data["whatsapp"]    as? String ?? ""
                coins        = data["coins"]       as? Int    ?? 0
                vehicleMake  = data["vehicleMake"]  as? String ?? ""
                vehicleModel = data["vehicleModel"] as? String ?? ""
                vehicleColor = data["vehicleColor"] as? String ?? ""
                vehiclePlate = data["vehiclePlate"] as? String ?? ""
                isOnline     = data["isAvailable"] as? Bool ?? true
                let rSum   = data["ratingSum"]   as? Int ?? 0
                let rCount = data["ratingCount"] as? Int ?? 0
                ratingAverage = rCount > 0 ? Double(rSum) / Double(rCount) : nil
            }
        } else {
            await MainActor.run {
                displayName = currentUser?.displayName ?? ""
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
                if let user = currentUser {
                    let req = user.createProfileChangeRequest()
                    req.displayName = trimmedName
                    try await req.commitChanges()
                }
                if let uid = currentUser?.uid {
                    var payload: [String: Any] = [
                        "displayName": trimmedName,
                        "phone":       phone,
                        "whatsapp":    whatsapp,
                    ]
                    if userState.role == .driver {
                        payload["vehicleMake"]  = vehicleMake
                        payload["vehicleModel"] = vehicleModel
                        payload["vehicleColor"] = vehicleColor
                        payload["vehiclePlate"] = vehiclePlate
                    }
                    try await db.collection("users").document(uid).setData(payload, merge: true)
                }
                await MainActor.run {
                    isSaving = false
                    showingSaveConfirmation = true
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView(role: .rider)
        .environmentObject(UserState())
        .environmentObject(LocationService())
}
