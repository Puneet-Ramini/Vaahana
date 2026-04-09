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

// Listens to Firebase auth state and exposes whether a verified phone user is signed in
class AuthState: ObservableObject {
    @Published var isSignedIn = false

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            // Only consider the user signed in if they have a verified phone number
            self?.isSignedIn = user?.phoneNumber != nil
        }
    }

    deinit {
        if let handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}

@main
struct VaahanaApp: App {
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
