import Foundation
import CoreLocation
import Combine

/// Centralized, observable location service for the whole app.
/// - Manages authorization (when-in-use vs always), accuracy, and update modes.
/// - Provides one-shot and continuous location updates.
/// - Exposes helpers to request/upgrade authorization and open Settings.
final class LocationService: NSObject, ObservableObject {
    // Public published properties
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy

    // Internals
    private let manager = CLLocationManager()
    private var isContinuous = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
    }

    // MARK: - Authorization

    /// Ask for When-In-Use permission. This is what iOS shows as Allow Once / Allow While Using.
    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Ask to upgrade to Always authorization. iOS will only show this if the app already has When-In-Use and the Info.plist has the Always key + background modes.
    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// Convenience: open Settings for the app so the user can manually change permissions.
    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Updates

    /// Start continuous high-accuracy updates (foreground use). If authorization is not granted yet, request When-In-Use first.
    func startUpdatingLocation() {
        isContinuous = true
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            // No-op; caller can observe authorizationStatus and show UI to open Settings
            break
        @unknown default:
            break
        }
    }

    /// Stop continuous updates.
    func stopUpdatingLocation() {
        isContinuous = false
        manager.stopUpdatingLocation()
    }

    /// One-shot current location with timeout. Requests authorization if needed.
    func requestCurrentLocation(timeout: TimeInterval = 5) async -> Result<CLLocation, LocationError> {
        // Quick path: if we already have a fresh cached location (<30s), return it.
        if let cached = manager.location, cached.timestamp.timeIntervalSinceNow > -30 {
            return .success(cached)
        }

        // Check global Location Services first
        guard CLLocationManager.locationServicesEnabled() else {
            return .failure(.servicesDisabled)
        }

        // Ensure at least when-in-use authorization
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            return .failure(.permissionDenied)
        @unknown default:
            break
        }

        return await withCheckedContinuation { continuation in
            var resumed = false
            func finish(_ result: Result<CLLocation, LocationError>) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }

            // Start a one-shot request
            manager.requestLocation()

            // Timeout watchdog
            let watchdog = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                finish(.failure(.timeout))
            }

            // Temporary delegate bridge
            let proxy = OneShotDelegate { result in
                watchdog.cancel()
                finish(result)
            }
            self.manager.delegate = proxy

            // After finishing, restore our delegate
            proxy.onFinish = { [weak self] in
                guard let self else { return }
                self.manager.delegate = self
            }
        }
    }
}

// MARK: - Errors

enum LocationError: LocalizedError {
    case servicesDisabled
    case permissionDenied
    case timeout
    case failed

    var errorDescription: String? {
        switch self {
        case .servicesDisabled: return "Location Services are turned off."
        case .permissionDenied: return "Location permission denied."
        case .timeout:          return "Timed out waiting for your location."
        case .failed:           return "Unable to fetch your location."
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        if isContinuous, authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let last = locations.last { location = last }
        if !isContinuous {
            manager.stopUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Nothing special here; observers can react via requestCurrentLocation's result
    }
}

// MARK: - One-shot delegate proxy

private final class OneShotDelegate: NSObject, CLLocationManagerDelegate {
    let handler: (Result<CLLocation, LocationError>) -> Void
    var onFinish: (() -> Void)?

    init(handler: @escaping (Result<CLLocation, LocationError>) -> Void) {
        self.handler = handler
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            handler(.success(loc))
        } else {
            handler(.failure(.failed))
        }
        onFinish?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clErr = error as? CLError, clErr.code == .denied {
            handler(.failure(.permissionDenied))
        } else {
            handler(.failure(.failed))
        }
        onFinish?()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            handler(.failure(.permissionDenied))
            onFinish?()
        case .notDetermined:
            break
        @unknown default:
            handler(.failure(.failed))
            onFinish?()
        }
    }
}
