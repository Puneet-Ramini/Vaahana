//
//  LocationPickerView.swift
//  Vaahana
//

import SwiftUI
import MapKit
import CoreLocation

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

private final class OneTimeLocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    func fetch() async -> CLLocationCoordinate2D? {
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        return await withCheckedContinuation { cont in
            self.continuation = cont
            self.manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        continuation?.resume(returning: locations.first?.coordinate)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
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
        Task {
            let fetcher = OneTimeLocationFetcher()
            guard let coord = await fetcher.fetch() else {
                await MainActor.run { isResolving = false }
                return
            }
            let geocoder = CLGeocoder()
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let placemarks = try? await geocoder.reverseGeocodeLocation(location)
            await MainActor.run {
                isResolving = false
                if let pm = placemarks?.first {
                    let name = pm.locality ?? pm.name ?? "Current Location"
                    let sub = [pm.administrativeArea, pm.isoCountryCode]
                        .compactMap { $0 }.joined(separator: ", ")
                    let result = PlaceResult(name: name, subtitle: sub, coordinate: coord)
                    onSelect(result)
                    dismiss()
                }
            }
        }
    }
}
