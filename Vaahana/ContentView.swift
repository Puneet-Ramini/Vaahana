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
        hotDuration            = (try? c.decodeIfPresent(Int.self, forKey: .hotDuration))              ?? 5
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

// MARK: - Tab Selection

enum MainTab: String, CaseIterable {
    case rides = "Rides"
    case map = "Map"
    case switchRole = "Switch"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .rides:      return "car.fill"
        case .map:        return "map"
        case .switchRole: return "arrow.triangle.2.circlepath"
        case .settings:   return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .rides:      return "car.fill"
        case .map:        return "map.fill"
        case .switchRole: return "arrow.triangle.2.circlepath"
        case .settings:   return "gearshape.fill"
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
                        if role == .rider {
                            RiderView()
                        } else {
                            DriverView()
                        }
                    case .map:
                        MapTabView(role: role)
                    case .switchRole:
                        SwitchRoleTab()
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
        if role == .rider {
            return MainTab.allCases.filter { $0 != .map }
        }
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
    @State private var showingPostSheet = false
    @State private var editingRide: Ride?
    @State private var showingActiveRide = false
    @State private var viewingBidsRide: Ride?
    @State private var ratingRide: Ride?
    @State private var showExpired = false
    @State private var showPast = false

    var expiredRides: [Ride] {
        storage.myRides.filter { $0.status == .expired }
    }

    var pastRides: [Ride] {
        storage.myRides.filter { $0.status == .completed || $0.status == .cancelled }
    }

    var postedRides: [Ride] {
        storage.myRides.filter { $0.status == .posted }
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
                        // Active ride banner
                        if let active = storage.activeRide {
                            activeRideBanner(active)
                        }

                        // Posted rides
                        if postedRides.isEmpty && storage.activeRide == nil {
                            emptyState
                        } else {
                            if !postedRides.isEmpty {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("Active Requests")
                                        .font(.title3).fontWeight(.bold)
                                    Text("\(postedRides.count)")
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.top, 4)
                            }

                            ForEach(postedRides) { ride in
                                CompactRideRow(ride: ride) {
                                    viewingBidsRide = ride
                                }
                                .contextMenu {
                                    Button { editingRide = ride } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) { storage.deleteRide(ride) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { storage.deleteRide(ride) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button { editingRide = ride } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }

                        // Expired rides — collapsible
                        if !expiredRides.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) { showExpired.toggle() }
                                } label: {
                                    HStack {
                                        Text("Expired")
                                            .font(.subheadline).fontWeight(.semibold)
                                        Text("\(expiredRides.count)")
                                            .font(.caption).fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                            .rotationEffect(.degrees(showExpired ? 90 : 0))
                                    }
                                    .foregroundStyle(.primary)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)

                                if showExpired {
                                    ForEach(expiredRides) { ride in
                                        HStack(spacing: 6) {
                                            CompactRideRow(ride: ride) { }
                                            Button {
                                                repostRide(ride)
                                            } label: {
                                                VStack(spacing: 2) {
                                                    Image(systemName: "arrow.clockwise")
                                                        .font(.system(size: 13, weight: .semibold))
                                                    Text("Re-post")
                                                        .font(.system(size: 9, weight: .medium))
                                                }
                                                .foregroundStyle(.blue)
                                                .frame(width: 54)
                                                .frame(maxHeight: .infinity)
                                                .background(Color.blue.opacity(0.08))
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }

                        // Past rides — collapsible
                        if !pastRides.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) { showPast.toggle() }
                                } label: {
                                    HStack {
                                        Text("Past Rides")
                                            .font(.subheadline).fontWeight(.semibold)
                                        Text("\(pastRides.count)")
                                            .font(.caption).fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                            .rotationEffect(.degrees(showPast ? 90 : 0))
                                    }
                                    .foregroundStyle(.primary)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)

                                if showPast {
                                    ForEach(pastRides) { ride in
                                        CompactRideRow(ride: ride) { }
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)  // More space for floating tab bar
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .overlay(alignment: .bottom) {
            if storage.activeRide == nil {
                Button {
                    showingPostSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                        Text("Request a Ride")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 84)  // More space for floating tab bar
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
                ZStack {
                    Circle().fill(Color.blue.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: "car.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ride in Progress").font(.caption).foregroundStyle(.secondary)
                    Text(ride.status.riderDisplayText)
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.blue)
                    Text("\(ride.from) → \(ride.to)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No ride requests yet")
                .font(.headline)
            Text("Post your first ride request and\nnearby drivers will reach out.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func repostRide(_ ride: Ride) {
        // Prevent duplicate: only allow if no posted ride exists with same route
        let alreadyPosted = storage.myRides.contains {
            $0.status == .posted && $0.from == ride.from && $0.to == ride.to
        }
        guard !alreadyPosted else { return }

        var newRide = ride
        newRide.id = UUID()
        newRide.status = .posted
        newRide.createdAt = Date()
        newRide.hotDuration = ride.hotDuration
        newRide.bidCount = 0
        newRide.selectedBidId = nil
        newRide.lowestBidCoins = nil
        newRide.latestBidAt = nil
        newRide.driverId = nil
        newRide.driverName = nil
        newRide.driverPhone = nil
        newRide.driverWhatsapp = nil
        storage.addRide(newRide)
        // Remove expired original
        storage.deleteRide(ride)
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

    var filteredRides: [(ride: Ride, distanceMiles: Double?)] {
        let hot = storage.hotPostedRides
        guard let center = mapCenter else {
            return hot.map { ($0, nil) }
        }
        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return hot
            .compactMap { ride -> (ride: Ride, distanceMiles: Double?)? in
                guard let lat = ride.pickupLat, let lng = ride.pickupLng else {
                    return (ride, nil)
                }
                let dist = centerLoc.distance(from: CLLocation(latitude: lat, longitude: lng)) / 1609.34
                guard dist <= filterRadius else { return nil }
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
                                     : "No requests within \(Int(filterRadius)) mi")
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

// MARK: - Ride Detail Sheet

struct RideDetailSheet: View {
    let ride: Ride
    @EnvironmentObject var storage: RideStorage
    @Environment(\.dismiss) var dismiss
    @State private var showingBidSheet = false
    @State private var existingBid: RideBid?
    @State private var isLoadingBid = false

    private var pickupCoord: CLLocationCoordinate2D? {
        guard let lat = ride.pickupLat, let lng = ride.pickupLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: Map
                    if let coord = pickupCoord {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                        ))) {
                            Annotation(ride.from, coordinate: coord) {
                                ZStack {
                                    Circle().fill(Color.blue).frame(width: 32, height: 32)
                                    Image(systemName: "mappin")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .shadow(color: .black.opacity(0.2), radius: 4)
                            }
                        }
                        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onTapGesture { openAppleMaps() }
                        .overlay(alignment: .bottomTrailing) {
                            Label("Open in Maps", systemImage: "arrow.up.right.square")
                                .font(.caption2).fontWeight(.medium)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .padding(8)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }

                    VStack(spacing: 14) {
                        // MARK: Route card
                        VStack(spacing: 14) {
                            // From → To
                            HStack(spacing: 12) {
                                VStack(spacing: 8) {
                                    Circle().fill(.green).frame(width: 10, height: 10)
                                    Rectangle().fill(Color(UIColor.separator)).frame(width: 1.5, height: 20)
                                    Image(systemName: "mappin.circle.fill").font(.system(size: 14)).foregroundStyle(.red)
                                }

                                VStack(alignment: .leading, spacing: 12) {
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
                                Divider().frame(height: 30)
                                detailStat(icon: "road.lanes", label: "Distance", value: String(format: "%.1f mi", ride.miles))
                                Divider().frame(height: 30)
                                detailStat(icon: "centsign.circle", label: "Coins", value: "🪙 \(ride.coins)")
                            }
                        }
                        .padding(14)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // MARK: Notes
                        if let notes = ride.notes, !notes.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "text.bubble.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.blue)
                                    .padding(.top, 2)
                                Text(notes)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(14)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        // MARK: Rider info
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.blue.gradient)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Text(ride.initials)
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ride.name).font(.subheadline).fontWeight(.semibold)
                                Text("Posted \(ride.timeAgo)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusChip(status: ride.status)
                        }
                        .padding(14)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // MARK: Actions
                        if ride.status == .posted {
                            VStack(spacing: 10) {
                                Button { showingBidSheet = true } label: {
                                    HStack(spacing: 8) {
                                        if isLoadingBid { ProgressView().tint(.white) }
                                        Image(systemName: existingBid == nil ? "hand.raised.fill" : "pencil.circle.fill")
                                        Text(existingBid == nil ? "Place Bid" : "Edit Your Bid")
                                    }
                                    .font(.headline).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .disabled(isLoadingBid)

                                Button { openWhatsApp() } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "message.fill")
                                        Text("WhatsApp")
                                    }
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundStyle(.green)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.green.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }

                                if let bid = existingBid {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green).font(.subheadline)
                                        Text("Your bid: 🪙 \(bid.bidCoins)")
                                            .font(.subheadline).fontWeight(.medium)
                                        Spacer()
                                        Text("Waiting for rider")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .background(Color.green.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        } else {
                            Button { openWhatsApp() } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "message.fill")
                                    Text("Message Rider")
                                }
                                .font(.headline).foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.green)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
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
        .sheet(isPresented: $showingBidSheet) {
            PlaceBidSheet(ride: ride, existingBid: existingBid)
        }
        .task { await loadExistingBid() }
    }

    // MARK: - Helpers

    private func detailStat(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14)).foregroundStyle(.blue)
            Text(value)
                .font(.caption).fontWeight(.semibold)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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

    private func openWhatsApp() {
        let cleanedCountryCode = ride.whatsappCountryCode.replacingOccurrences(of: "+", with: "")
        let message = "Hi \(ride.name)! I saw your ride request on Vaahana (\(ride.from) → \(ride.to), \(ride.coins) coins). I'd love to help — interested?"
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://wa.me/\(cleanedCountryCode)\(ride.whatsappPhone)?text=\(encodedMessage)") {
            UIApplication.shared.open(url)
        }
    }

    private func openAppleMaps() {
        guard let coord = pickupCoord else { return }
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        destination.name = ride.from
        destination.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
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

struct MapTabView: View {
    let role: UserRole
    @EnvironmentObject var storage: RideStorage
    @EnvironmentObject var locationService: LocationService
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedRide: Ride?
    @State private var showControls = true
    @AppStorage("filterRadius") private var filterRadius = 5.0
    @AppStorage("driverCenterLat") private var driverCenterLat: Double = 0
    @AppStorage("driverCenterLon") private var driverCenterLon: Double = 0
    @AppStorage("driverCenterCustom") private var driverCenterCustom: Bool = false

    private var radiusMeters: CLLocationDistance { filterRadius * 1609.34 }

    private var mapCenter: CLLocationCoordinate2D? {
        if role == .driver && driverCenterCustom {
            return CLLocationCoordinate2D(latitude: driverCenterLat, longitude: driverCenterLon)
        }
        return locationService.location?.coordinate
    }

    private var ridesForMap: [Ride] {
        if role == .rider {
            return storage.myRides.filter { !$0.status.isFinal && $0.pickupLat != nil && $0.pickupLng != nil }
        }
        let hot = storage.hotPostedRides
        guard let center = mapCenter else { return hot }
        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return hot.filter { ride in
            guard let lat = ride.pickupLat, let lng = ride.pickupLng else { return true }
            return centerLoc.distance(from: CLLocation(latitude: lat, longitude: lng)) / 1609.34 <= filterRadius
        }
    }

    var body: some View {
        ZStack {
            // Full-screen map
            MapReader { proxy in
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

                    // Radius circle (driver only)
                    if role == .driver, let center = mapCenter {
                        MapCircle(center: center, radius: radiusMeters)
                            .foregroundStyle(Color.blue.opacity(0.08))
                            .stroke(Color.blue.opacity(0.4), lineWidth: 1.5)

                        if driverCenterCustom {
                            Annotation("Search Center", coordinate: center) {
                                ZStack {
                                    Circle().fill(Color.blue).frame(width: 32, height: 32)
                                    Image(systemName: "scope")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .shadow(color: .black.opacity(0.2), radius: 4)
                            }
                        }
                    }

                    // Ride pins
                    ForEach(ridesForMap) { ride in
                        if let lat = ride.pickupLat, let lng = ride.pickupLng {
                            Annotation(ride.from, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                                mapPin(for: ride)
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .mapControls {
                    MapCompass()
                }
                .onTapGesture { screenPoint in
                    guard role == .driver else { return }
                    if let coord = proxy.convert(screenPoint, from: .local) {
                        withAnimation(.spring(response: 0.3)) {
                            driverCenterLat = coord.latitude
                            driverCenterLon = coord.longitude
                            driverCenterCustom = true
                            cameraPosition = .region(MKCoordinateRegion(
                                center: coord,
                                latitudinalMeters: radiusMeters * 3,
                                longitudinalMeters: radiusMeters * 3
                            ))
                        }
                    }
                }
            }

            // Overlays
            VStack(spacing: 0) {
                Spacer()

                // Bottom control card
                if role == .driver {
                    driverControlCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    riderInfoCard
                }
            }
            .padding(.bottom, 8)

            // Top-right buttons
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        // Re-center button
                        Button {
                            recenterMap()
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.blue)
                                .frame(width: 40, height: 40)
                                .background(.ultraThickMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.1), radius: 4)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
        }
        .onAppear {
            recenterMapOnAppear()
        }
        .sheet(item: $selectedRide) { ride in
            RideDetailSheet(ride: ride)
        }
    }
    
    // MARK: - Helper Methods
    
    private func recenterMap() {
        if let loc = locationService.location {
            driverCenterCustom = false
            withAnimation(.spring(response: 0.3)) {
                let meters = role == .driver ? radiusMeters * 3 : 5000.0
                cameraPosition = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            }
        }
    }
    
    private func recenterMapOnAppear() {
        if let loc = locationService.location {
            let center = (role == .driver && driverCenterCustom)
                ? CLLocationCoordinate2D(latitude: driverCenterLat, longitude: driverCenterLon)
                : loc.coordinate
            let meters = role == .driver ? radiusMeters * 3 : 5000.0
            cameraPosition = .region(MKCoordinateRegion(
                center: center,
                latitudinalMeters: meters,
                longitudinalMeters: meters
            ))
        }
    }

    // MARK: - Driver Control Card

    private var driverControlCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
                Text("Tap map to set location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(ridesForMap.count) ride\(ridesForMap.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text("Radius")
                    .font(.caption).foregroundStyle(.secondary)
                Slider(value: $filterRadius, in: 1...50, step: 1)
                    .tint(.blue)
                    .onChange(of: filterRadius) { _, _ in
                        if let center = mapCenter {
                            withAnimation(.spring(response: 0.3)) {
                                cameraPosition = .region(MKCoordinateRegion(
                                    center: center,
                                    latitudinalMeters: radiusMeters * 3,
                                    longitudinalMeters: radiusMeters * 3
                                ))
                            }
                        }
                    }
                Text("\(Int(filterRadius)) mi")
                    .font(.system(.caption, design: .rounded)).fontWeight(.bold)
                    .foregroundStyle(.blue)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 56)
    }

    // MARK: - Rider Info Card

    @ViewBuilder
    private var riderInfoCard: some View {
        let activeRides = storage.myRides.filter { !$0.status.isFinal }
        if !activeRides.isEmpty {
            VStack(spacing: 8) {
                ForEach(activeRides) { ride in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.blue.opacity(0.12)).frame(width: 36, height: 36)
                            Image(systemName: "car.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ride.status.riderDisplayText)
                                .font(.subheadline).fontWeight(.semibold)
                            Text("\(ride.from) → \(ride.to)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        StatusChip(status: ride.status)
                    }
                }
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            .padding(.horizontal, 12)
            .padding(.bottom, 80)  // Space for floating tab bar
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
