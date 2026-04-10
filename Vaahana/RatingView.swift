//
//  RatingView.swift
//  Vaahana
//
//  Post-ride star rating prompt. Shown once after a ride completes.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct RatingView: View {
    let ride: Ride
    let raterRole: UserRole   // who is submitting the rating
    let targetUid: String     // who is being rated

    @Environment(\.dismiss) private var dismiss

    @State private var stars = 0
    @State private var comment = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var targetLabel: String {
        raterRole == .rider ? "your driver" : "your rider"
    }
    private var targetName: String {
        raterRole == .rider ? (ride.driverName ?? "Your Driver") : ride.name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 10) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.yellow)
                        Text("How was the ride?")
                            .font(.title2).fontWeight(.bold)
                        Text("Rate \(targetLabel): **\(targetName)**")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 16)

                    // Star selector
                    HStack(spacing: 14) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                withAnimation(.spring(response: 0.2)) { stars = star }
                            } label: {
                                Image(systemName: star <= stars ? "star.fill" : "star")
                                    .font(.system(size: 44))
                                    .foregroundStyle(star <= stars ? .yellow : Color(UIColor.systemGray3))
                                    .scaleEffect(star == stars ? 1.15 : 1.0)
                            }
                        }
                    }

                    // Rating label
                    Text(ratingLabel)
                        .font(.headline)
                        .foregroundStyle(stars > 0 ? .primary : .clear)
                        .animation(.easeIn(duration: 0.15), value: stars)

                    // Comment
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Comment (optional)")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("What stood out?", text: $comment, axis: .vertical)
                            .lineLimit(3...5)
                            .padding(12)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    if let error = errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    // Submit
                    Button { submit() } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text(stars == 0 ? "Skip" : "Submit Rating")
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(stars > 0 ? Color.black : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(isSubmitting)
                    .padding(.horizontal)
                }
                .padding(.bottom, 32)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
        }
    }

    private var ratingLabel: String {
        switch stars {
        case 1: return "Poor"
        case 2: return "Fair"
        case 3: return "Good"
        case 4: return "Great"
        case 5: return "Excellent!"
        default: return ""
        }
    }

    private func submit() {
        guard stars > 0 else { dismiss(); return }
        guard let uid = Auth.auth().currentUser?.uid, !targetUid.isEmpty else { dismiss(); return }
        isSubmitting = true
        errorMessage = nil

        let db = Firestore.firestore()
        let ratingDoc: [String: Any] = [
            "rideId":    ride.id.uuidString,
            "raterUid":  uid,
            "ratedUid":  targetUid,
            "stars":     stars,
            "comment":   comment,
            "raterRole": raterRole.rawValue,
            "createdAt": FieldValue.serverTimestamp(),
        ]

        Task {
            do {
                let batch = db.batch()
                // Write rating document
                let ratingRef = db.collection("ratings").document()
                batch.setData(ratingDoc, forDocument: ratingRef)
                // Increment rated user's aggregate stats
                let userRef = db.collection("users").document(targetUid)
                batch.updateData([
                    "ratingSum":   FieldValue.increment(Int64(stars)),
                    "ratingCount": FieldValue.increment(Int64(1)),
                ], forDocument: userRef)
                try await batch.commit()
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = "Could not save rating. Try again."
                    isSubmitting = false
                }
            }
        }
    }
}
