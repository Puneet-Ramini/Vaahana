//
//  VaahanaApp.swift
//  Vaahana
//
//  Created by Puneet Ramini on 4/6/26.
//

import SwiftUI
import Combine
import FirebaseCore
import FirebaseAuth
import UIKit

// MARK: - App Delegate
// Required for Firebase Phone Auth to receive APNs tokens and remote notifications

class AppDelegate: NSObject, UIApplicationDelegate {

    // Forward APNs device token to Firebase Auth
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
    }

    // Forward remote notifications to Firebase Auth (used for silent push verification)
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        completionHandler(.noData)
    }

    // Forward URL opens to Firebase Auth (used for reCAPTCHA redirect on simulator)
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return Auth.auth().canHandle(url)
    }
}

// MARK: - Auth State

class AuthState: ObservableObject {
    @Published var isSignedIn = false

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.isSignedIn = user?.phoneNumber != nil
        }
    }

    deinit {
        if let handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}

// MARK: - App Entry Point

@main
struct VaahanaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authState = AuthState()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            if authState.isSignedIn {
                ContentView()
            } else {
                PhoneAuthView()
            }
        }
    }
}
