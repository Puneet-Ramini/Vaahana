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
    @State private var role: UserRole? = nil
    @State private var ratingAverage: Double? = nil
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingHistory = false

    // Driver vehicle info
    @State private var vehicleMake  = ""
    @State private var vehicleModel = ""
    @State private var vehicleColor = ""
    @State private var vehiclePlate = ""

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

                // Role
                Section {
                    HStack {
                        Label(role == .driver ? "Driver" : "Rider",
                              systemImage: role == .driver ? "car.fill" : "figure.wave")
                        Spacer()
                        Text("Role").font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Account")
                }

                // Rating badge
                if let avg = ratingAverage {
                    Section {
                        HStack {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                            Text(String(format: "%.1f", avg))
                                .fontWeight(.semibold)
                            Text("avg rating")
                                .foregroundStyle(.secondary)
                        }
                    }
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

                if role == .driver {
                    Section {
                        TextField("Make (e.g. Toyota)", text: $vehicleMake)
                        TextField("Model (e.g. Camry)", text: $vehicleModel)
                        TextField("Color", text: $vehicleColor)
                        TextField("License Plate", text: $vehiclePlate)
                            .autocapitalization(.allCharacters)
                    } header: {
                        Text("Vehicle")
                    } footer: {
                        Text("Shown to riders when you accept a ride.")
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    NavigationLink {
                        RideHistoryView(role: role ?? .rider)
                    } label: {
                        Label("Ride History", systemImage: "clock.arrow.circlepath")
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
        if let data = try? await db.collection("users").document(uid).getDocument().data() {
            displayName  = data["displayName"] as? String ?? currentUser?.displayName ?? ""
            phone        = data["phone"]       as? String ?? ""
            whatsapp     = data["whatsapp"]    as? String ?? ""
            vehicleMake  = data["vehicleMake"]  as? String ?? ""
            vehicleModel = data["vehicleModel"] as? String ?? ""
            vehicleColor = data["vehicleColor"] as? String ?? ""
            vehiclePlate = data["vehiclePlate"] as? String ?? ""
            if let rawRole = data["role"] as? String {
                role = UserRole(rawValue: rawRole)
            }
            let rSum   = data["ratingSum"]   as? Int ?? 0
            let rCount = data["ratingCount"] as? Int ?? 0
            ratingAverage = rCount > 0 ? Double(rSum) / Double(rCount) : nil
        } else {
            displayName = currentUser?.displayName ?? ""
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
                if let user = currentUser {
                    let req = user.createProfileChangeRequest()
                    req.displayName = trimmedName
                    try await req.commitChanges()
                }
                if let uid = currentUser?.uid {
                    var payload: [String: Any] = [
                        "displayName": trimmedName,
                        "phone":       phone,
                        "whatsapp":    whatsapp,
                    ]
                    if role == .driver {
                        payload["vehicleMake"]  = vehicleMake
                        payload["vehicleModel"] = vehicleModel
                        payload["vehicleColor"] = vehicleColor
                        payload["vehiclePlate"] = vehiclePlate
                    }
                    try await db.collection("users").document(uid).setData(payload, merge: true)
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
