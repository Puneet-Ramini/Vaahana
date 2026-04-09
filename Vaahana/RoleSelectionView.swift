// RoleSelectionView.swift
// Vaahana

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct RoleSelectionView: View {
    let onRoleSelected: (UserRole) -> Void

    @State private var isSaving = false
    @State private var errorMessage: String?
    private let db = Firestore.firestore()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Text("Vaahana")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                    Text("How will you use Vaahana?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                VStack(spacing: 16) {
                    RoleCard(
                        icon: "figure.wave",
                        title: "I need a ride",
                        subtitle: "Post ride requests. Earn coins when drivers help you.",
                        color: .blue,
                        isLoading: isSaving,
                        onSelect: { save(.rider) }
                    )

                    RoleCard(
                        icon: "car.fill",
                        title: "I'm a driver",
                        subtitle: "Browse nearby hot requests. Help your community, earn coins.",
                        color: .black,
                        isLoading: isSaving,
                        onSelect: { save(.driver) }
                    )
                }
                .padding(.horizontal)
            }

            Spacer()

            Text("Your role is permanent and cannot be changed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func save(_ role: UserRole) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await db.collection("users").document(uid).setData(
                    ["role": role.rawValue], merge: true
                )
                await MainActor.run {
                    isSaving = false
                    onRoleSelected(role)
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

// MARK: - Role Card

struct RoleCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isLoading: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
