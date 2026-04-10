//
//  LocationPickerView.swift
//  Vaahana
//

import SwiftUI
import Combine
import MapKit
import CoreLocation
import UIKit

// MARK: - PlaceResult

struct PlaceResult: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D

    var displayTitle: String { name }
    var displaySubtitle: String { subtitle }

    static func == (lhs: PlaceResult, rhs: PlaceResult) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - LocationCompleter (MKLocalSearchCompleter wrapper)

@MainActor
final class LocationCompleter: NSObject, ObservableObject {
    @Published var completions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        if query.isEmpty {
            completions = []
            return
        }
        completer.queryFragment = query
    }
}

extension LocationCompleter: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.completions = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.completions = []
        }
    }
}

// MARK: - One-shot location fetcher

@MainActor
private final class OneTimeLocationFetcher: NSObject, CLLocationManagerDelegate {
    enum FetchResult {
        case success(CLLocationCoordinate2D)
        case permissionDenied
        case failed(Error?)
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<FetchResult, Never>?

    override init() {
        super.init()
        // Manager must be set up on main thread
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func fetch() async -> FetchResult {
        let status = manager.authorizationStatus

        if status == .denied || status == .restricted {
            return .permissionDenied
        }

        if status == .authorizedWhenInUse || status == .authorizedAlways {
            // Return cached location immediately if it's fresh (< 30 seconds old)
            if let cached = manager.location,
               cached.timestamp.timeIntervalSinceNow > -30 {
                return .success(cached.coordinate)
            }
            return await requestLocation()
        }

        // Not determined — request permission, then location
        return await withCheckedContinuation { cont in
            self.continuation = cont
            self.manager.requestWhenInUseAuthorization()
        }
    }

    private func requestLocation() async -> FetchResult {
        await withCheckedContinuation { cont in
            self.continuation = cont
            self.manager.requestLocation()
        }
    }

    func cancel() {
        continuation?.resume(returning: .failed(nil))
        continuation = nil
        manager.delegate = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let coordinate = locations.first?.coordinate else {
                continuation?.resume(returning: .failed(nil))
                continuation = nil
                return
            }
            continuation?.resume(returning: .success(coordinate))
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let clError = error as? CLError, clError.code == .denied {
                continuation?.resume(returning: .permissionDenied)
            } else {
                continuation?.resume(returning: .failed(error))
            }
            continuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                // Check cache first, then request
                if let cached = self.manager.location,
                   cached.timestamp.timeIntervalSinceNow > -30 {
                    continuation?.resume(returning: .success(cached.coordinate))
                    continuation = nil
                } else {
                    self.manager.requestLocation()
                }
            case .denied, .restricted:
                continuation?.resume(returning: .permissionDenied)
                continuation = nil
            case .notDetermined:
                break
            @unknown default:
                continuation?.resume(returning: .failed(nil))
                continuation = nil
            }
        }
    }
}

// MARK: - LocationPickerView

struct LocationPickerView: View {
    let title: String
    let onSelect: (PlaceResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var completer = LocationCompleter()
    @State private var searchText = ""
    @State private var isResolving = false
    @State private var locationError: LocationError? = nil
    @State private var locationFetcher: OneTimeLocationFetcher? = nil

    enum LocationError: Identifiable {
        case locationServicesDisabled
        case permissionDenied
        case timedOut
        case fetchFailed

        var id: Int {
            switch self {
            case .locationServicesDisabled: return 0
            case .permissionDenied: return 1
            case .timedOut: return 2
            case .fetchFailed: return 3
            }
        }

        var title: String {
            switch self {
            case .locationServicesDisabled: return "Location Services Off"
            case .permissionDenied: return "Location Access Denied"
            case .timedOut: return "Location Timed Out"
            case .fetchFailed:      return "Couldn't Get Location"
            }
        }
        var message: String {
            switch self {
            case .locationServicesDisabled:
                return "Turn on Location Services in Settings → Privacy & Security → Location Services."
            case .permissionDenied: return "To use your current location, go to Settings → Vaahana → Location and allow access."
            case .timedOut:
                return "We waited for your location, but no GPS fix arrived. Try again in a place with better signal."
            case .fetchFailed:      return "Unable to determine your location. Please search for your address manually."
            }
        }
        var showSettings: Bool {
            switch self {
            case .permissionDenied:
                return true
            case .locationServicesDisabled, .timedOut, .fetchFailed:
                return false
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    fetchCurrentLocation()
                } label: {
                    Label("Use Current Location", systemImage: "location.fill")
                        .foregroundStyle(.blue)
                }

                ForEach(completer.completions, id: \.self) { completion in
                    Button {
                        resolve(completion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(completion.title)
                                .foregroundStyle(.primary)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search places or addresses"
            )
            .onChange(of: searchText) { _, newValue in
                completer.update(query: newValue)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isResolving {
                    ZStack {
                        Color.black.opacity(0.15).ignoresSafeArea()
                        ProgressView("Finding location…")
                            .padding()
                            .background(.regularMaterial)
                            .cornerRadius(12)
                    }
                }
            }
            .alert(item: $locationError) { error in
                if error.showSettings {
                    Alert(
                        title: Text(error.title),
                        message: Text(error.message),
                        primaryButton: .default(Text("Open Settings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        },
                        secondaryButton: .cancel()
                    )
                } else {
                    Alert(
                        title: Text(error.title),
                        message: Text(error.message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
    }

    // MARK: - Resolve a search completion to a coordinate

    private func resolve(_ completion: MKLocalSearchCompletion) {
        isResolving = true
        let request = MKLocalSearch.Request(completion: completion)
        Task {
            let response = try? await MKLocalSearch(request: request).start()
            await MainActor.run {
                isResolving = false
                if let item = response?.mapItems.first {
                    let result = PlaceResult(
                        name: item.name ?? completion.title,
                        subtitle: completion.subtitle,
                        coordinate: item.placemark.coordinate
                    )
                    onSelect(result)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Current device location

    private func fetchCurrentLocation() {
        isResolving = true
        let fetcher = OneTimeLocationFetcher()
        locationFetcher = fetcher          // retain until done
        Task {
            let result = await fetchCurrentCoordinate(using: fetcher)
            await MainActor.run {
                locationFetcher = nil
                switch result {
                case .success(let coord):
                    // Keep spinner up while geocoding (3s timeout then fall back to coords)
                    Task {
                        let clLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                        let placemarks = try? await withThrowingTaskGroup(of: [CLPlacemark]?.self) { group in
                            group.addTask { try await CLGeocoder().reverseGeocodeLocation(clLocation) }
                            group.addTask {
                                try await Task.sleep(for: .seconds(3))
                                return nil
                            }
                            let result = try await group.next() ?? nil
                            group.cancelAll()
                            return result
                        }
                        await MainActor.run {
                            isResolving = false
                            let place: PlaceResult
                            if let pm = placemarks?.first {
                                let name = pm.locality ?? pm.subLocality ?? pm.name ?? "Current Location"
                                let sub  = [pm.administrativeArea, pm.isoCountryCode]
                                    .compactMap { $0 }.joined(separator: ", ")
                                place = PlaceResult(name: name, subtitle: sub, coordinate: coord)
                            } else {
                                let subtitle = String(format: "%.5f, %.5f", coord.latitude, coord.longitude)
                                place = PlaceResult(name: "Current Location", subtitle: subtitle, coordinate: coord)
                            }
                            onSelect(place)
                            dismiss()
                        }
                    }
                case .locationServicesDisabled:
                    isResolving = false
                    locationError = .locationServicesDisabled
                case .permissionDenied:
                    isResolving = false
                    locationError = .permissionDenied
                case .timedOut:
                    isResolving = false
                    locationError = .timedOut
                case .fetchFailed:
                    isResolving = false
                    locationError = .fetchFailed
                }
            }
        }
    }

    private func fetchCurrentCoordinate(using fetcher: OneTimeLocationFetcher) async -> LocationErrorOrCoordinate {
        if !CLLocationManager.locationServicesEnabled() {
            return .locationServicesDisabled
        }

        // Run fetch with a 5-second watchdog on the main actor
        return await withCheckedContinuation { @MainActor outer in
            var resumed = false
            func finish(_ r: LocationErrorOrCoordinate) {
                guard !resumed else { return }
                resumed = true
                outer.resume(returning: r)
            }

            let watchdog = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                fetcher.cancel()
                finish(.timedOut)
            }

            Task { @MainActor in
                let result: LocationErrorOrCoordinate
                switch await fetcher.fetch() {
                case .success(let coord): result = .success(coord)
                case .permissionDenied:   result = .permissionDenied
                case .failed:             result = .fetchFailed
                }
                watchdog.cancel()
                finish(result)
            }
        }
    }
}

private enum LocationErrorOrCoordinate {
    case success(CLLocationCoordinate2D)
    case locationServicesDisabled
    case permissionDenied
    case timedOut
    case fetchFailed
}
