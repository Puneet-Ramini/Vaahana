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

// MARK: - Data Models

struct Ride: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var phone: String
    var phoneCountryCode: String
    var whatsappPhone: String
    var whatsappCountryCode: String
    var from: String
    var to: String
    var miles: Double
    var coins: Int                 // community coins offered for this ride
    var hotDuration: Int           // minutes the request stays visible (default 5)
    var pickupDate: Date
    var status: RideStatus
    var createdAt: Date

    var hotUntil: Date { createdAt.addingTimeInterval(TimeInterval(hotDuration * 60)) }
    var isHot: Bool { hotUntil > Date() }
    
    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
    
    var pickupDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: pickupDate)
    }
    
    var pickupDateShort: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: pickupDate)
    }
}

enum RideStatus: String, Codable {
    case pending, accepted
}

enum UserRole: String, Codable {
    case rider
    case driver
}

// MARK: - Storage Manager

class RideStorage: ObservableObject {
    @Published var rides: [Ride] = []
    @Published var myRideIDs: [UUID] = []
    @Published var isLoading = true

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    init() {
        loadMyRideIDs()
        startListening()
    }

    deinit {
        listener?.remove()
    }

    private func loadMyRideIDs() {
        guard let data = UserDefaults.standard.data(forKey: "myRideIDs"),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return }
        myRideIDs = ids
    }

    private func persistMyRideIDs() {
        if let encoded = try? JSONEncoder().encode(myRideIDs) {
            UserDefaults.standard.set(encoded, forKey: "myRideIDs")
        }
    }

    private func startListening() {
        listener = db.collection("rides")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.rides = snapshot.documents.compactMap { try? $0.data(as: Ride.self) }
                self.isLoading = false
            }
    }

    func addRide(_ ride: Ride) {
        try? db.collection("rides").document(ride.id.uuidString).setData(from: ride)
        myRideIDs.append(ride.id)
        persistMyRideIDs()
    }

    func updateRide(_ ride: Ride) {
        try? db.collection("rides").document(ride.id.uuidString).setData(from: ride)
    }

    func deleteRide(_ ride: Ride) {
        db.collection("rides").document(ride.id.uuidString).delete()
        myRideIDs.removeAll { $0 == ride.id }
        persistMyRideIDs()
    }

    var myRides: [Ride] {
        rides.filter { myRideIDs.contains($0.id) }
    }

    var pendingRides: [Ride] {
        rides.filter { $0.status == .pending }
    }

    var acceptedRides: [Ride] {
        rides.filter { $0.status == .accepted }
    }

    var hotPendingRides: [Ride] {
        rides.filter { $0.status == .pending && $0.isHot }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    let role: UserRole
    @StateObject private var storage = RideStorage()
    @State private var showingProfile = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Vaahana")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                Spacer()
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
    }
}

// MARK: - Rider View

struct RiderView: View {
    @EnvironmentObject var storage: RideStorage
    @State private var showingPostSheet = false
    @State private var editingRide: Ride?
    
    var body: some View {
        ZStack {
            if storage.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if storage.myRides.isEmpty {
                // Empty State
                VStack(spacing: 16) {
                    Text("🚗")
                        .font(.system(size: 72))
                    Text("No requests yet")
                        .font(.headline)
                    Text("Post your first ride request.\nDrivers nearby will reach out on WhatsApp.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(storage.myRides.sorted(by: { $0.createdAt > $1.createdAt })) { ride in
                            RideCard(ride: ride, isDriverMode: false, onEdit: {
                                editingRide = ride
                            }, onDelete: {
                                deleteRide(ride)
                            })
                        }
                    }
                    .padding()
                    .padding(.bottom, 80) // Space for button
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
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
        .sheet(isPresented: $showingPostSheet) {
            PostRideSheet()
        }
        .sheet(item: $editingRide) { ride in
            PostRideSheet(editingRide: ride)
        }
    }
    
    func deleteRide(_ ride: Ride) {
        storage.deleteRide(ride)
    }
}

// MARK: - Driver View

struct DriverView: View {
    @EnvironmentObject var storage: RideStorage
    @State private var selectedRide: Ride?
    @State private var rideLocations: [UUID: CLLocationCoordinate2D] = [:]
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasSetInitialCamera = false
    @StateObject private var locationManager = LocationManager()

    // Persisted filter settings
    @AppStorage("filterRadius") private var filterRadius = 5.0
    @AppStorage("driverCenterLat") private var driverCenterLat: Double = 0
    @AppStorage("driverCenterLon") private var driverCenterLon: Double = 0
    @AppStorage("driverCenterCustom") private var driverCenterCustom: Bool = false

    var effectiveCenter: CLLocationCoordinate2D? {
        if driverCenterCustom {
            return CLLocationCoordinate2D(latitude: driverCenterLat, longitude: driverCenterLon)
        }
        return locationManager.location?.coordinate
    }

    var radiusMeters: CLLocationDistance { filterRadius * 1609.34 }

    var filteredRides: [Ride] {
        let hot = storage.hotPendingRides
        guard let center = effectiveCenter else { return hot }
        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return hot.filter { ride in
            guard let coord = rideLocations[ride.id] else { return true }
            return (centerLoc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude)) / 1609.34) <= filterRadius
        }
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // ── Map ──
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        // Live location dot
                        if let loc = locationManager.location {
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
                        if let center = effectiveCenter {
                            MapCircle(center: center, radius: radiusMeters)
                                .foregroundStyle(Color.blue.opacity(0.1))
                                .stroke(Color.blue, lineWidth: 2)

                            // Custom-center pin
                            if driverCenterCustom {
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

                        // Ride pins
                        ForEach(filteredRides) { ride in
                            if let loc = rideLocations[ride.id] {
                                Annotation(ride.from, coordinate: loc) {
                                    rideAnnotationView(for: ride)
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
                .frame(height: geo.size.height * 0.52)

                // ── Bottom control panel ──
                controlPanel
            }
        }
        .task { await loadRideLocations() }
        .onChange(of: storage.rides) { _, _ in Task { await loadRideLocations() } }
        .onAppear { locationManager.requestLocation() }
        .sheet(item: $selectedRide) { ride in RideDetailSheet(ride: ride) }
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 12)

            // Location + radius
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Image(systemName: driverCenterCustom ? "mappin.circle.fill" : "location.fill")
                                .foregroundStyle(driverCenterCustom ? .orange : .blue)
                            Text(driverCenterCustom ? "Custom Location" : "Live Location")
                                .font(.subheadline).fontWeight(.semibold)
                        }
                        Text(driverCenterCustom
                             ? "Tap the map to move your search area"
                             : "Tap anywhere on the map to pin a location")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if driverCenterCustom {
                        Button {
                            driverCenterCustom = false
                            if let loc = locationManager.location {
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
                Text("🔥 Hot Requests").font(.subheadline).fontWeight(.semibold)
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
                    Image(systemName: storage.hotPendingRides.isEmpty ? "flame.slash" : "map.circle")
                        .font(.title2).foregroundStyle(.secondary)
                    Text(storage.hotPendingRides.isEmpty
                         ? "No hot requests right now"
                         : "No hot requests within \(Int(filterRadius)) mi")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredRides.sorted { $0.hotUntil < $1.hotUntil }) { ride in
                            CompactRideRow(ride: ride) { selectedRide = ride }
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
        Button { selectedRide = ride } label: {
            ZStack {
                Circle().fill(Color.orange).frame(width: 44, height: 44)
                VStack(spacing: 1) {
                    Image(systemName: "figure.wave")
                        .font(.system(size: 13)).foregroundStyle(.white)
                    Text("🪙\(ride.coins)")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
    }

    // MARK: - Data

    func loadRideLocations() async {
        let calculator = DistanceCalculator()
        var locations = rideLocations
        for ride in storage.rides where locations[ride.id] == nil {
            if let coord = try? await calculator.geocode(address: ride.from) {
                locations[ride.id] = CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lon)
            }
        }
        await MainActor.run {
            rideLocations = locations
            guard !hasSetInitialCamera else { return }
            hasSetInitialCamera = true
            if let center = effectiveCenter {
                cameraPosition = .region(MKCoordinateRegion(
                    center: center,
                    latitudinalMeters: radiusMeters * 3,
                    longitudinalMeters: radiusMeters * 3
                ))
            } else if let first = locations.values.first {
                cameraPosition = .region(MKCoordinateRegion(
                    center: first,
                    span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
                ))
            }
        }
    }
}

// MARK: - Location Manager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }
    
    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first
        manager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

// MARK: - Compact Ride Row

struct CompactRideRow: View {
    let ride: Ride
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
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
                        Text("\(String(format: "%.1f", ride.miles)) mi")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("•").foregroundStyle(.secondary)
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
                    .fill(ride.status == .pending ? Color.black : Color.green)
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
    @State private var showingAcceptConfirmation = false
    
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
                    if ride.status == .pending {
                        VStack(spacing: 12) {
                            Button {
                                openWhatsApp()
                            } label: {
                                Label("Text on WhatsApp", systemImage: "message.fill")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .cornerRadius(12)
                            }
                            
                            Button {
                                showingAcceptConfirmation = true
                            } label: {
                                Label("Accept Ride", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.black)
                                    .cornerRadius(12)
                            }
                        }
                    } else {
                        Button {
                            openWhatsApp()
                        } label: {
                            Label("Message Rider", systemImage: "message.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
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
            .confirmationDialog("Accept this ride?", isPresented: $showingAcceptConfirmation) {
                Button("Accept Ride") {
                    acceptRide()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You'll be connected with \(ride.name) via WhatsApp to finalize pickup details.")
            }
        }
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
    
    @State private var goingTo = ""
    @State private var pickupFrom = ""
    @State private var milesText = ""
    @State private var coinsText = ""
    @State private var hotDuration = 5
    @State private var pickupDate = Date()
    @State private var name = ""
    @State private var phoneCountryCode = "+1"
    @State private var phone = ""
    @State private var whatsappCountryCode = "+1"
    @State private var whatsappPhone = ""
    @State private var sameNumberForBoth = true
    @State private var isCalculatingDistance = false
    @State private var distanceError: String?
    
    private let distanceCalculator = DistanceCalculator()
    
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
    
    var miles: Double {
        Double(milesText) ?? 0
    }
    
    var coins: Int {
        Int(coinsText) ?? 0
    }

    var suggestedCoins: Int {
        max(1, Int(miles))
    }

    var isValid: Bool {
        !goingTo.isEmpty &&
        !pickupFrom.isEmpty &&
        miles > 0 &&
        coins > 0 &&
        !name.isEmpty &&
        phone.count >= 6 &&
        (sameNumberForBoth || whatsappPhone.count >= 6)
    }
    
    var canCalculateDistance: Bool {
        !pickupFrom.isEmpty && !goingTo.isEmpty && !isCalculatingDistance
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pickup Location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g. Boston, MA", text: $pickupFrom)
                            .font(.body)
                            .onChange(of: pickupFrom) { oldValue, newValue in
                                distanceError = nil
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Drop-off Location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g. Nashua, NH", text: $goingTo)
                            .font(.body)
                            .onChange(of: goingTo) { oldValue, newValue in
                                distanceError = nil
                            }
                    }
                    
                    VStack(spacing: 8) {
                        HStack {
                            TextField("0.0", text: $milesText)
                                .keyboardType(.decimalPad)
                                .font(.body)
                                .disabled(isCalculatingDistance)
                                .onChange(of: milesText) { oldValue, newValue in
                                    if coinsText.isEmpty || Int(coinsText) == max(1, Int(Double(oldValue) ?? 0)) {
                                        if let milesValue = Double(newValue) {
                                            coinsText = "\(max(1, Int(milesValue)))"
                                        }
                                    }
                                }
                            
                            if isCalculatingDistance {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            
                            Text("miles")
                                .foregroundStyle(.secondary)
                        }
                        
                        if canCalculateDistance {
                            Button {
                                calculateDistance()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Calculate Distance")
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if let error = distanceError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Route")
                }
                
                // Date & Time Section
                Section {
                    DatePicker("Pickup Date & Time", selection: $pickupDate, in: Date()...)
                        .datePickerStyle(.compact)
                } header: {
                    Text("When")
                } footer: {
                    Text("Select when you need to be picked up")
                }
                
                // Coins Section
                Section {
                    HStack {
                        Text("🪙")
                            .font(.title3)
                        TextField("0", text: $coinsText)
                            .keyboardType(.numberPad)
                            .font(.title3)
                            .fontWeight(.semibold)

                        if miles > 0 && suggestedCoins != coins {
                            Button {
                                coinsText = "\(suggestedCoins)"
                            } label: {
                                Text("Use \(suggestedCoins)")
                                    .font(.caption)
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

                // Hot Duration Section
                Section {
                    Stepper("\(hotDuration) minutes", value: $hotDuration, in: 5...60, step: 5)
                } header: {
                    Text("Keep Request Active For")
                } footer: {
                    Text("Your request disappears from drivers after this time. Default is 5 minutes.")
                }
                
                Section {
                    TextField("e.g. John Doe", text: $name)
                        .font(.body)
                    
                    HStack(spacing: 8) {
                        Picker("Code", selection: $phoneCountryCode) {
                            ForEach(countryCodes, id: \.1) { flag, code in
                                Text("\(flag) \(code)").tag(code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                        
                        TextField("Phone number", text: $phone)
                            .keyboardType(.numberPad)
                            .font(.body)
                    }
                    
                    Toggle(isOn: $sameNumberForBoth) {
                        Text("Same number for WhatsApp")
                            .font(.subheadline)
                    }
                    
                    if !sameNumberForBoth {
                        HStack(spacing: 8) {
                            Picker("Code", selection: $whatsappCountryCode) {
                                ForEach(countryCodes, id: \.1) { flag, code in
                                    Text("\(flag) \(code)").tag(code)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 100)
                            
                            TextField("WhatsApp number", text: $whatsappPhone)
                                .keyboardType(.numberPad)
                                .font(.body)
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
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    submitRide()
                } label: {
                    Text(editingRide == nil ? "Post Ride Request" : "Update Ride Request")
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
            .onAppear {
                loadEditingData()
            }
        }
    }
    
    func loadEditingData() {
        guard let ride = editingRide else { return }
        goingTo = ride.to
        pickupFrom = ride.from
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
    }
    
    func submitRide() {
        let finalWhatsappPhone = sameNumberForBoth ? phone : whatsappPhone
        let finalWhatsappCountryCode = sameNumberForBoth ? phoneCountryCode : whatsappCountryCode
        
        if let editingRide = editingRide {
            var updatedRide = editingRide
            updatedRide.name = name
            updatedRide.phone = phone
            updatedRide.phoneCountryCode = phoneCountryCode
            updatedRide.whatsappPhone = finalWhatsappPhone
            updatedRide.whatsappCountryCode = finalWhatsappCountryCode
            updatedRide.from = pickupFrom
            updatedRide.to = goingTo
            updatedRide.miles = miles
            updatedRide.coins = coins
            updatedRide.hotDuration = hotDuration
            updatedRide.pickupDate = pickupDate
            storage.updateRide(updatedRide)
        } else {
            let ride = Ride(
                id: UUID(),
                name: name,
                phone: phone,
                phoneCountryCode: phoneCountryCode,
                whatsappPhone: finalWhatsappPhone,
                whatsappCountryCode: finalWhatsappCountryCode,
                from: pickupFrom,
                to: goingTo,
                miles: miles,
                coins: coins,
                hotDuration: hotDuration,
                pickupDate: pickupDate,
                status: .pending,
                createdAt: Date()
            )
            storage.addRide(ride)
        }
        
        dismiss()
    }
    
    func calculateDistance() {
        Task {
            isCalculatingDistance = true
            distanceError = nil
            
            do {
                let calculatedMiles = try await distanceCalculator.calculateDistance(
                    from: pickupFrom,
                    to: goingTo
                )
                
                await MainActor.run {
                    milesText = String(format: "%.1f", calculatedMiles)
                    coinsText = "\(max(1, Int(calculatedMiles)))"
                    isCalculatingDistance = false
                }
            } catch {
                await MainActor.run {
                    distanceError = "Could not calculate distance. Please enter manually."
                    isCalculatingDistance = false
                }
            }
        }
    }
}

// MARK: - Ride Card

struct RideCard: View {
    let ride: Ride
    let isDriverMode: Bool
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
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
            
            // Actions
            if ride.status == .pending {
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
    
    var body: some View {
        HStack(spacing: 4) {
            if status == .pending {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                Text("Pending")
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 10))
                Text("Accepted")
            }
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(status == .pending ? Color.secondary : Color.green)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(status == .pending ? Color.gray.opacity(0.15) : Color.green.opacity(0.15))
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
}
