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
import FirebaseFirestore

// MARK: - User State

class UserState: ObservableObject {
    @Published var isSignedIn = false
    @Published var role: UserRole? = nil
    @Published var isLoadingRole = true

    private var handle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.isSignedIn = user != nil
                if let uid = user?.uid {
                    self?.fetchRole(uid: uid)
                } else {
                    self?.role = nil
                    self?.isLoadingRole = false
                }
            }
        }
    }

    func fetchRole(uid: String) {
        db.collection("users").document(uid).getDocument { [weak self] doc, _ in
            DispatchQueue.main.async {
                if let rawRole = doc?.data()?["role"] as? String,
                   let role = UserRole(rawValue: rawRole) {
                    self?.role = role
                } else {
                    self?.role = nil
                }
                self?.isLoadingRole = false
            }
        }
    }

    deinit {
        if let handle { Auth.auth().removeStateDidChangeListener(handle) }
    }
}

// MARK: - App Entry Point

@main
struct VaahanaApp: App {
    @StateObject private var userState = UserState()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            if !userState.isSignedIn {
                AuthView()
            } else if userState.isLoadingRole {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground))
            } else if let role = userState.role {
                ContentView(role: role)
            } else {
                RoleSelectionView { selectedRole in
                    userState.role = selectedRole
                }
            }
        }
    }
}
