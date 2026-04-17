//
//  VaahanaApp.swift
//  Vaahana
//

import SwiftUI
import Combine
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif
import CoreLocation
import UIKit

// MARK: - App Delegate (notifications + FCM when available)

#if canImport(FirebaseMessaging)
final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        Messaging.messaging().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid)
            .setData(["fcmToken": fcmToken], merge: true)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }
}
#else
// FirebaseMessaging not yet added — basic notification delegate only
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }
}
#endif

// MARK: - User State

class UserState: ObservableObject {
    @Published var isSignedIn       = false
    @Published var role: UserRole?  = nil
    @Published var isLoadingRole    = true
    @Published var showProfileSetup = false   // shown once per login if name/phone missing
    @Published var isAdmin          = false

    // Cached profile fields — used to decide whether to show setup sheet
    var displayName: String = ""
    var phone: String       = ""

    private var handle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.isSignedIn = user != nil
                if let uid = user?.uid {
                    self?.fetchRole(uid: uid)
                } else {
                    self?.role              = nil
                    self?.showProfileSetup  = false
                    self?.isLoadingRole     = false
                }
            }
        }
    }

    func fetchRole(uid: String) {
        db.collection("users").document(uid).getDocument { [weak self] doc, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let data = doc?.data()

                // Resolve role
                if let rawRole = data?["role"] as? String,
                   let role = UserRole(rawValue: rawRole) {
                    self.role = role
                } else {
                    self.role = nil
                }

                // Cache profile fields and decide if setup sheet is needed
                self.displayName    = data?["displayName"] as? String
                                      ?? Auth.auth().currentUser?.displayName
                                      ?? ""
                self.phone          = data?["phone"] as? String ?? ""
                let profileComplete = !self.displayName.trimmingCharacters(in: .whitespaces).isEmpty
                                      && !self.phone.isEmpty
                self.showProfileSetup = !profileComplete
                self.isAdmin         = data?["isAdmin"] as? Bool ?? false

                // Refresh FCM token binding after login (token may have changed)
                #if canImport(FirebaseMessaging)
                if let token = Messaging.messaging().fcmToken {
                    self.db.collection("users").document(uid).setData(["fcmToken": token], merge: true)
                }
                #endif

                // Daily coin grant: 100 coins per day to every user
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let today = formatter.string(from: Date())
                let lastGrant = data?["lastDailyCoinDate"] as? String ?? ""
                if lastGrant != today {
                    var grant: [String: Any] = [
                        "coins":             FieldValue.increment(Int64(100)),
                        "lastDailyCoinDate": today,
                    ]
                    // Ensure coinsLocked exists for users created before we added it
                    if data?["coinsLocked"] == nil { grant["coinsLocked"] = 0 }
                    self.db.collection("users").document(uid).setData(grant, merge: true)
                }

                self.isLoadingRole = false
            }
        }
    }

    deinit {
        if let handle { Auth.auth().removeStateDidChangeListener(handle) }
    }
}

// MARK: - Location Service

class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum RequestError: Error {
        case servicesDisabled
        case permissionDenied
        case timeout
        case failed
    }

    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var pendingLocationContinuation: CheckedContinuation<Result<CLLocationCoordinate2D, RequestError>, Never>?
    private var pendingBestLocation: CLLocation?
    private var pendingDesiredAccuracy: CLLocationAccuracy = 35
    private var pendingAuthorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationTimeoutTask: Task<Void, Never>?
    private var authorizationTimeoutTask: Task<Void, Never>?

    override init() {
        authorizationStatus = CLLocationManager().authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus

        // Keep legacy app behavior: ask early so map-based screens can center quickly.
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func requestCurrentLocation(timeout: TimeInterval = 5) async -> Result<CLLocationCoordinate2D, RequestError> {
        if let cached = manager.location,
           cached.timestamp.timeIntervalSinceNow > -15,
           cached.horizontalAccuracy > 0,
           cached.horizontalAccuracy <= 50 {
            return .success(cached.coordinate)
        }

        guard CLLocationManager.locationServicesEnabled() else {
            return .failure(.servicesDisabled)
        }

        let status = await ensureAuthorized(timeout: min(timeout, 6))
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .restricted, .denied:
            return .failure(.permissionDenied)
        case .notDetermined:
            return .failure(.timeout)
        @unknown default:
            return .failure(.failed)
        }

        return await withCheckedContinuation { continuation in
            if let pending = pendingLocationContinuation {
                pending.resume(returning: .failure(.failed))
            }
            pendingBestLocation = nil
            pendingDesiredAccuracy = 35
            pendingLocationContinuation = continuation
            manager.requestLocation()

            locationTimeoutTask?.cancel()
            locationTimeoutTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if let continuation = self.pendingLocationContinuation {
                    if let best = self.pendingBestLocation {
                        continuation.resume(returning: .success(best.coordinate))
                    } else {
                        continuation.resume(returning: .failure(.timeout))
                    }
                    self.pendingLocationContinuation = nil
                    self.pendingBestLocation = nil
                }
            }
        }
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func ensureAuthorized(timeout: TimeInterval) async -> CLAuthorizationStatus {
        let current = manager.authorizationStatus
        switch current {
        case .authorizedWhenInUse, .authorizedAlways, .denied, .restricted:
            return current
        case .notDetermined:
            break
        @unknown default:
            return current
        }

        return await withCheckedContinuation { continuation in
            if let pending = pendingAuthorizationContinuation {
                pending.resume(returning: manager.authorizationStatus)
            }
            pendingAuthorizationContinuation = continuation

            manager.requestWhenInUseAuthorization()

            authorizationTimeoutTask?.cancel()
            authorizationTimeoutTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if let continuation = self.pendingAuthorizationContinuation {
                    continuation.resume(returning: self.manager.authorizationStatus)
                    self.pendingAuthorizationContinuation = nil
                }
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if let continuation = pendingAuthorizationContinuation,
           manager.authorizationStatus != .notDetermined {
            authorizationTimeoutTask?.cancel()
            continuation.resume(returning: manager.authorizationStatus)
            pendingAuthorizationContinuation = nil
        }

        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        location = latest

        guard let continuation = pendingLocationContinuation else { return }

        let validLocations = locations.filter { $0.horizontalAccuracy > 0 }
        guard let bestInBatch = validLocations.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) else {
            return
        }

        if let currentBest = pendingBestLocation {
            if bestInBatch.horizontalAccuracy < currentBest.horizontalAccuracy {
                pendingBestLocation = bestInBatch
            }
        } else {
            pendingBestLocation = bestInBatch
        }

        if let best = pendingBestLocation, best.horizontalAccuracy <= pendingDesiredAccuracy {
            locationTimeoutTask?.cancel()
            continuation.resume(returning: .success(best.coordinate))
            pendingLocationContinuation = nil
            pendingBestLocation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }

        locationTimeoutTask?.cancel()
        if let continuation = pendingLocationContinuation {
            if let clError = error as? CLError, clError.code == .denied {
                continuation.resume(returning: .failure(.permissionDenied))
            } else {
                if let best = pendingBestLocation {
                    continuation.resume(returning: .success(best.coordinate))
                } else {
                    continuation.resume(returning: .failure(.failed))
                }
            }
            pendingLocationContinuation = nil
            pendingBestLocation = nil
        }
        print("Location manager failed: \(error.localizedDescription)")
    }
}

// MARK: - App Entry Point

@main
struct VaahanaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var userState = UserState()
    @StateObject private var locationService = LocationService()
    @State private var showSplash = true

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                mainContent
                    .opacity(showSplash ? 0 : 1)

                if showSplash {
                    SplashScreenView()
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                        .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.5), value: showSplash)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if !userState.isSignedIn {
            AuthView()
                .environmentObject(locationService)
        } else if userState.isLoadingRole {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
        } else if let role = userState.role {
            ContentView(role: role)
                .id(role)
                .environmentObject(userState)
                .environmentObject(locationService)
                .sheet(isPresented: $userState.showProfileSetup) {
                    ProfileSetupView(userState: userState)
                }
        } else {
            RoleSelectionView { selectedRole in
                userState.role = selectedRole
            }
        }
    }
}

// MARK: - Splash Screen

struct SplashScreenView: View {
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            Image("Vaahana Logo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
        }
    }
}

// MARK: - Profile Setup View

/// Shown once after login when the user's name or phone number is missing.
/// Pre-fills PostRideSheet on next ride post. Can be skipped.
struct ProfileSetupView: View {
    @ObservedObject var userState: UserState
    @Environment(\.dismiss) private var dismiss

    @State private var name  = ""
    @State private var phone = ""
    @State private var isSaving   = false
    @State private var errorMessage: String?

    private let db = Firestore.firestore()
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && phone.count >= 5 && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.blue)
                        Text("Complete your profile")
                            .font(.title2).fontWeight(.bold)
                        Text("Your name and number are saved and pre-filled every time you post a ride request.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                }

                Section("Your Details") {
                    TextField("Full name", text: $name)
                        .autocorrectionDisabled()
                        .textContentType(.name)
                    TextField("Phone / WhatsApp number", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                    }
                }
            }
        }
        .onAppear {
            // Pre-fill with any partial data already in UserState
            name  = userState.displayName
            phone = userState.phone
        }
    }

    private func save() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        isSaving = true
        errorMessage = nil
        Task {
            do {
                // Update display name in Firebase Auth
                let req = Auth.auth().currentUser?.createProfileChangeRequest()
                req?.displayName = trimmedName
                try await req?.commitChanges()

                // Save to Firestore
                try await db.collection("users").document(uid).setData([
                    "displayName": trimmedName,
                    "phone":       phone,
                    "whatsapp":    phone,
                ], merge: true)

                await MainActor.run {
                    userState.displayName = trimmedName
                    userState.phone       = phone
                    isSaving              = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving     = false
                }
            }
        }
    }
}
