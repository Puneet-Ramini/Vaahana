//
//  ContentView.swift
//  Vaahana
//
//  Created by Puneet Ramini on 4/6/26.
//

import SwiftUI
import Combine
import MapKit

// MARK: - Data Models

struct Ride: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var phone: String              // US phone - digits only, no country code
    var phoneCountryCode: String   // US phone country code
    var whatsappPhone: String      // WhatsApp - digits only, no country code
    var whatsappCountryCode: String // WhatsApp country code
    var from: String               // pickup city/area
    var to: String                 // destination city/area
    var miles: Double
    var price: Double              // rider's willing to pay amount
    var pickupDate: Date           // Date and time of pickup
    var status: RideStatus
    var createdAt: Date
    
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

enum AppMode: String, CaseIterable {
    case rider = "Rider"
    case driver = "Driver"
}

// MARK: - Storage Manager

class RideStorage: ObservableObject {
    @AppStorage("rides") private var ridesData: Data = Data()
    @AppStorage("myRideIDs") private var myRideIDsData: Data = Data()
    
    @Published var rides: [Ride] = []
    @Published var myRideIDs: [UUID] = []
    
    init() {
        loadRides()
        loadMyRideIDs()
    }
    
    private func loadRides() {
        if let decoded = try? JSONDecoder().decode([Ride].self, from: ridesData) {
            rides = decoded
        }
    }
    
    private func loadMyRideIDs() {
        if let decoded = try? JSONDecoder().decode([UUID].self, from: myRideIDsData) {
            myRideIDs = decoded
        }
    }
    
    func saveRides() {
        if let encoded = try? JSONEncoder().encode(rides) {
            ridesData = encoded
        }
    }
    
    func saveMyRideIDs() {
        if let encoded = try? JSONEncoder().encode(myRideIDs) {
            myRideIDsData = encoded
        }
    }
    
    func addRide(_ ride: Ride) {
        rides.append(ride)
        myRideIDs.append(ride.id)
        saveRides()
        saveMyRideIDs()
    }
    
    func updateRide(_ ride: Ride) {
        if let index = rides.firstIndex(where: { $0.id == ride.id }) {
            rides[index] = ride
            saveRides()
        }
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
}

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var storage = RideStorage()
    @State private var selectedMode: AppMode = .rider
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Vaahana")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .padding(.horizontal)
                    .padding(.top, 16)
                
                // Mode Picker
                Picker("Mode", selection: $selectedMode) {
                    ForEach(AppMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .background(Color(UIColor.systemBackground))
            
            // Content
            Group {
                switch selectedMode {
                case .rider:
                    RiderView()
                case .driver:
                    DriverView()
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .environmentObject(storage)
    }
}

// MARK: - Rider View

struct RiderView: View {
    @EnvironmentObject var storage: RideStorage
    @State private var showingPostSheet = false
    @State private var editingRide: Ride?
    
    var body: some View {
        ZStack {
            if storage.myRides.isEmpty {
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
        storage.rides.removeAll { $0.id == ride.id }
        storage.myRideIDs.removeAll { $0 == ride.id }
        storage.saveRides()
        storage.saveMyRideIDs()
    }
}

// MARK: - Driver View

struct DriverView: View {
    @EnvironmentObject var storage: RideStorage
    @State private var selectedRide: Ride?
    @State private var showingList = true
    @State private var showingFilters = false
    @State private var showingRideDetail = false
    @State private var rideLocations: [UUID: CLLocationCoordinate2D] = [:]
    @State private var cameraPosition: MapCameraPosition = .automatic
    @StateObject private var locationManager = LocationManager()
    
    // Filter settings
    @AppStorage("filterCity") private var filterCity = ""
    @AppStorage("filterRadius") private var filterRadius = 50.0
    @State private var tempFilterCity = ""
    @State private var tempFilterRadius = 50.0
    
    var filteredRides: [Ride] {
        guard !filterCity.isEmpty, let userLocation = locationManager.location else {
            return storage.rides
        }
        
        return storage.rides.filter { ride in
            guard let rideLocation = rideLocations[ride.id] else { return false }
            let distance = userLocation.distance(from: CLLocation(latitude: rideLocation.latitude, longitude: rideLocation.longitude))
            let miles = distance / 1609.34
            return miles <= filterRadius
        }
    }
    
    var body: some View {
        ZStack {
            if storage.rides.isEmpty {
                emptyStateView
            } else {
                mapViewWithList
            }
        }
        .task {
            await loadRideLocations()
        }
        .onChange(of: storage.rides) { oldValue, newValue in
            Task {
                await loadRideLocations()
            }
        }
        .onAppear {
            locationManager.requestLocation()
            tempFilterCity = filterCity
            tempFilterRadius = filterRadius
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingFilters = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                        if !filterCity.isEmpty {
                            Text("\(Int(filterRadius))mi")
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            filterSheet
        }
        .sheet(item: $selectedRide) { ride in
            RideDetailSheet(ride: ride)
        }
    }
    
    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Boston, MA", text: $tempFilterCity)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Radius")
                            Spacer()
                            Text("\(Int(tempFilterRadius)) miles")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $tempFilterRadius, in: 5...200, step: 5)
                    }
                } header: {
                    Text("Filter Settings")
                } footer: {
                    Text("Show only ride requests within this radius from your location")
                }
                
                Section {
                    Button("Clear Filters") {
                        tempFilterCity = ""
                        tempFilterRadius = 50
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingFilters = false
                        tempFilterCity = filterCity
                        tempFilterRadius = filterRadius
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filterCity = tempFilterCity
                        filterRadius = tempFilterRadius
                        showingFilters = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("🚗")
                .font(.system(size: 72))
            Text("No rides available")
                .font(.headline)
            Text("Check back soon for ride requests")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var mapViewWithList: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Map - takes remaining space
                mapView
                    .frame(height: showingList ? geometry.size.height / 2 : geometry.size.height)
                
                // List - half screen
                if showingList {
                    listView
                        .frame(height: geometry.size.height / 2)
                }
            }
        }
    }
    
    private var mapView: some View {
        Map(position: $cameraPosition) {
            // User location - blue pulsing dot
            if let userLocation = locationManager.location {
                Annotation("My Location", coordinate: userLocation.coordinate) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 40, height: 40)
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 20, height: 20)
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 20, height: 20)
                    }
                    .shadow(color: .blue.opacity(0.4), radius: 8)
                }
            }
            
            // Ride locations
            ForEach(filteredRides) { ride in
                if let location = rideLocations[ride.id] {
                    Annotation(ride.from, coordinate: location) {
                        rideAnnotationView(for: ride)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
    }
    
    private func rideAnnotationView(for ride: Ride) -> some View {
        Button {
            selectedRide = ride
        } label: {
            ZStack {
                Circle()
                    .fill(ride.status == .pending ? Color.black : Color.green)
                    .frame(width: 44, height: 44)
                
                VStack(spacing: 2) {
                    Image(systemName: "figure.wave")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                    Text("$\(String(format: "%.0f", ride.price))")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
    }
    
    private var listView: some View {
        VStack(spacing: 0) {
            // Toggle button
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showingList.toggle()
                }
            } label: {
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 40, height: 5)
                        .padding(.top, 8)
                    
                    HStack {
                        Text("Ride Requests")
                            .font(.headline)
                        if !filterCity.isEmpty {
                            Text("(\(filteredRides.count))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: showingList ? "chevron.down" : "chevron.up")
                            .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .buttonStyle(.plain)
            .background(Color(UIColor.systemBackground))
            
            Divider()
            
            // Ride list - compact view
            ScrollView {
                LazyVStack(spacing: 8) {
                    let pendingFiltered = filteredRides.filter { $0.status == .pending }
                    let acceptedFiltered = filteredRides.filter { $0.status == .accepted }
                    
                    if !pendingFiltered.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Waiting for driver")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            
                            ForEach(pendingFiltered.sorted(by: { $0.createdAt > $1.createdAt })) { ride in
                                CompactRideRow(ride: ride) {
                                    selectedRide = ride
                                }
                            }
                        }
                    }
                    
                    if !acceptedFiltered.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirmed")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            
                            ForEach(acceptedFiltered.sorted(by: { $0.createdAt > $1.createdAt })) { ride in
                                CompactRideRow(ride: ride) {
                                    selectedRide = ride
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .background(Color(UIColor.systemBackground))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Prevent infinite scroll by limiting drag
                        if value.translation.height < -50 {
                            showingList = false
                        }
                    }
            )
        }
    }
    
    private func rideCardView(for ride: Ride) -> some View {
        RideCard(ride: ride, isDriverMode: true)
            .onTapGesture {
                if let location = rideLocations[ride.id] {
                    selectedRide = ride
                    withAnimation {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: location,
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        ))
                    }
                }
            }
    }
    
    func loadRideLocations() async {
        let calculator = DistanceCalculator()
        var locations: [UUID: CLLocationCoordinate2D] = [:]
        
        for ride in storage.rides {
            if let coord = try? await calculator.geocode(address: ride.from) {
                locations[ride.id] = CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lon)
            }
        }
        
        await MainActor.run {
            rideLocations = locations
            
            // Set initial camera position to user location or first ride
            if let userLocation = locationManager.location {
                cameraPosition = .region(MKCoordinateRegion(
                    center: userLocation.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
                ))
            } else if let firstLocation = locations.values.first {
                cameraPosition = .region(MKCoordinateRegion(
                    center: firstLocation,
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("$\(String(format: "%.0f", ride.price))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
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
                                Text("Offer")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("$\(String(format: "%.2f", ride.price))")
                                    .font(.headline)
                                    .foregroundStyle(.blue)
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
        let message = "Hi \(ride.name)! I saw your Vaahana request (\(ride.from) → \(ride.to), $\(String(format: "%.2f", ride.price))). I can give you a ride — interested?"
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://wa.me/\(cleanedCountryCode)\(ride.whatsappPhone)?text=\(encodedMessage)"
        
        if let url = URL(string: urlString) {
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
    @State private var priceText = ""
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
    
    var price: Double {
        Double(priceText) ?? 0
    }
    
    var suggestedPrice: Double {
        miles * 1.0
    }
    
    var isValid: Bool {
        !goingTo.isEmpty &&
        !pickupFrom.isEmpty &&
        miles > 0 &&
        price > 0 &&
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
                                    if priceText.isEmpty || Double(priceText) == (Double(oldValue) ?? 0) * 1.0 {
                                        if let milesValue = Double(newValue) {
                                            priceText = String(format: "%.0f", milesValue * 1.0)
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
                
                // Price Section
                Section {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0", text: $priceText)
                            .keyboardType(.decimalPad)
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        if miles > 0 && suggestedPrice != price {
                            Button {
                                priceText = String(format: "%.0f", suggestedPrice)
                            } label: {
                                Text("Use $\(String(format: "%.0f", suggestedPrice))")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Your Offer")
                } footer: {
                    if miles > 0 {
                        Text("Suggested: $\(String(format: "%.2f", suggestedPrice)) ($1 per mile)")
                    }
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
        priceText = String(format: "%.0f", ride.price)
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
            // Update existing ride
            var updatedRide = editingRide
            updatedRide.name = name
            updatedRide.phone = phone
            updatedRide.phoneCountryCode = phoneCountryCode
            updatedRide.whatsappPhone = finalWhatsappPhone
            updatedRide.whatsappCountryCode = finalWhatsappCountryCode
            updatedRide.from = pickupFrom
            updatedRide.to = goingTo
            updatedRide.miles = miles
            updatedRide.price = price
            updatedRide.pickupDate = pickupDate
            
            storage.updateRide(updatedRide)
        } else {
            // Create new ride
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
                price: price,
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
                    priceText = String(format: "%.0f", calculatedMiles * 1.0)
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
                InfoChip(text: String(format: "$%.2f", ride.price), color: .blue)
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
        let message = "Hi \(ride.name)! I saw your Vaahana request (\(ride.from) → \(ride.to), $\(String(format: "%.2f", ride.price))). I can give you a ride — interested?"
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://wa.me/\(cleanedCountryCode)\(ride.whatsappPhone)?text=\(encodedMessage)"
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
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
    ContentView()
}
