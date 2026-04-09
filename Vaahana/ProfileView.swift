// ProfileView.swift
// Vaahana

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var phone = ""
    @State private var whatsapp = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var currentUser: FirebaseAuth.User? { Auth.auth().currentUser }
    private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            Form {
                // Avatar + email
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 72, height: 72)
                                .overlay(
                                    Text(initials)
                                        .font(.system(size: 26, weight: .semibold))
                                        .foregroundStyle(.white)
                                )
                            Text(currentUser?.email ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("Profile") {
                    TextField("Display Name", text: $displayName)
                        .autocorrectionDisabled()
                }

                Section {
                    TextField("Phone number", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("WhatsApp number", text: $whatsapp)
                        .keyboardType(.phonePad)
                } header: {
                    Text("Contact Numbers")
                } footer: {
                    Text("These will auto-fill when you post a ride request.")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        try? Auth.auth().signOut()
                    } label: {
                        Text("Sign Out")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                    }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Computed

    private var initials: String {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            return String(currentUser?.email?.prefix(2) ?? "?").uppercased()
        }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Data

    private func load() async {
        guard let uid = currentUser?.uid else { return }
        displayName = currentUser?.displayName ?? ""
        if let data = try? await db.collection("users").document(uid).getDocument().data() {
            phone = data["phone"] as? String ?? ""
            whatsapp = data["whatsapp"] as? String ?? ""
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                // Update display name in Firebase Auth
                if let user = currentUser {
                    let req = user.createProfileChangeRequest()
                    req.displayName = displayName.trimmingCharacters(in: .whitespaces)
                    try await req.commitChanges()
                }
                // Save contact numbers to Firestore
                if let uid = currentUser?.uid {
                    try await db.collection("users").document(uid).setData(
                        ["phone": phone, "whatsapp": whatsapp],
                        merge: true
                    )
                }
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
