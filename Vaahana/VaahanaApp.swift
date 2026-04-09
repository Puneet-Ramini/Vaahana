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

// MARK: - Auth State

class AuthState: ObservableObject {
    @Published var isSignedIn = false

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.isSignedIn = user != nil
            }
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
    @StateObject private var authState = AuthState()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            if authState.isSignedIn {
                ContentView()
            } else {
                AuthView()
            }
        }
    }
}
