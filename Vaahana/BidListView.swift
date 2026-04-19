//
//  BidListView.swift
//  Vaahana
//
//  Rider view: live list of driver responses on a posted ride.
//  Rider chooses one to accept.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct BidListView: View {
    let ride: Ride

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var storage: RideStorage
    @State private var bids: [RideBid] = []
    @State private var isLoading = true
    @State private var isSelecting = false
    @State private var errorMessage: String?
    @State private var listenerReg: ListenerRegistration?
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false

    private let db = Firestore.firestore()

    var activeBids: [RideBid] {
        bids
            .filter { $0.status == .active }
            .sorted(by: { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) })
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading bids…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if activeBids.isEmpty {
                    emptyState
                } else {
                    bidList
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Driver Bids (\(activeBids.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showingEditSheet = true } label: {
                            Label("Edit Request", systemImage: "pencil")
                        }
                        Button(role: .destructive) { showingDeleteAlert = true } label: {
                            Label("Delete Request", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                PostRideSheet(editingRide: ride)
            }
            .alert("Delete Ride?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    storage.deleteRide(ride)
                    dismiss()
                }
            } message: {
                Text("This will permanently remove the ride request and all bids.")
            }
            .safeAreaInset(edge: .bottom) {
                if let error = errorMessage {
                    Text(error)
                        .font(.caption).foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(UIColor.systemBackground))
                }
            }
        }
        .onAppear { startListening() }
        .onDisappear { listenerReg?.remove() }
    }

    // MARK: - Bid List

    private var bidList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Summary header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Needed \(ride.pickupDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Posted \(ride.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    Spacer()
                    Text("Sorted: newest first")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)

                ForEach(activeBids) { bid in
                    bidCard(bid)
                }
            }
            .padding()
        }
    }

    // MARK: - Bid Card

    private func bidCard(_ bid: RideBid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Driver header
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 46, height: 46)
                    .overlay {
                        Text(bid.initials)
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(bid.driverName).font(.headline)
                    Text(bid.timeAgo).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Optional message
            if let msg = bid.message, !msg.isEmpty {
                Text("\"\(msg)\"")
                    .font(.subheadline).foregroundStyle(.secondary).italic()
                    .padding(.horizontal, 4)
            }

            Divider()

            // Action buttons
            HStack(spacing: 10) {
                Button { openWhatsApp(bid: bid) } label: {
                    Label("Message", systemImage: "message.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                }

                Button { selectBid(bid) } label: {
                    Label("Choose Driver", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelecting ? Color.gray : Color.black)
                        .cornerRadius(8)
                }
                .disabled(isSelecting)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.05), radius: 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 52)).foregroundStyle(.secondary)
            Text("No bids yet")
                .font(.headline)
            Text("Drivers will bid on your request soon.\nYour ride is live for \(ride.hotDuration) minutes.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func selectBid(_ bid: RideBid) {
        isSelecting = true
        errorMessage = nil
        Task {
            do {
                try await RideService.shared.selectBid(ride: ride, bid: bid)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSelecting = false
                }
            }
        }
    }

    private func openWhatsApp(bid: RideBid) {
        let msg = "Hi \(bid.driverName), I saw your response on Vaahana for \(ride.from) → \(ride.to). Are you available?"
        let encoded = msg.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let cleaned = bid.driverWhatsapp.replacingOccurrences(of: " ", with: "")
        if let url = URL(string: "https://wa.me/\(cleaned)?text=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Listener

    private func startListening() {
        let rideRef = db.collection("rides").document(ride.id.uuidString)
        listenerReg = rideRef.collection("bids")
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                bids = snapshot.documents.compactMap { try? $0.data(as: RideBid.self) }
                isLoading = false
            }
    }
}
