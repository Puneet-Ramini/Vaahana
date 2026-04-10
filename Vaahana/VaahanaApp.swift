//
//  VaahanaApp.swift
//  Vaahana
//

import SwiftUI
import Combine
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// MARK: - User State

class UserState: ObservableObject {
    @Published var isSignedIn      = false
    @Published var role: UserRole? = nil
    @Published var isLoadingRole   = true
    @Published var showProfileSetup = false   // shown once per login if name/phone missing

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
