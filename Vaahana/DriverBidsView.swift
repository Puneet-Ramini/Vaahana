//
//  DriverBidsView.swift
//  Vaahana
//
//  Driver's "My Bids" control center.
//  Segmented view showing Pending / Selected / Closed bids across all rides.
//

import SwiftUI
import FirebaseFirestore

struct DriverBidsView: View {
    @StateObject private var store = DriverBidsStore()
    @State private var selectedTab = 0   // 0=Pending, 1=Selected, 2=Closed
    @State private var enrichedPending:  [DriverBidEntry] = []
    @State private var enrichedSelected: [DriverBidEntry] = []
    @State private var enrichedClosed:   [DriverBidEntry] = []
    @State private var isEnriching = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented picker
                Picker("Tab", selection: $selectedTab) {
                    Text("Pending (\(store.pendingBids.count))").tag(0)
                    Text("Selected (\(store.selectedBids.count))").tag(1)
                    Text("Closed (\(store.closedBids.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()

                if store.isLoading || isEnriching {
                    Spacer()
                    ProgressView("Loading bids…")
                    Spacer()
                } else {
                    let entries: [DriverBidEntry] = {
                        switch selectedTab {
                        case 0: return enrichedPending
                        case 1: return enrichedSelected
                        default: return enrichedClosed
                        }
                    }()

                    if entries.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(entries) { entry in
                                    BidEntryCard(entry: entry)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("My Bids")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: store.pendingBids.count + store.selectedBids.count + store.closedBids.count) {
                await enrich()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(["No pending bids", "No selected bids", "No closed bids"][selectedTab])
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func enrich() async {
        isEnriching = true
        async let p = store.enrichEntries(store.pendingBids)
        async let s = store.enrichEntries(store.selectedBids)
        async let c = store.enrichEntries(store.closedBids)
        let (ep, es, ec) = await (p, s, c)
        enrichedPending  = ep
        enrichedSelected = es
        enrichedClosed   = ec
        isEnriching = false
    }
}

// MARK: - Bid Entry Card

private struct BidEntryCard: View {
    let entry: DriverBidEntry
    @State private var isWorking = false
    @State private var errorMsg: String?
    @State private var showingEdit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Route
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.blue)
                if entry.rideFrom.isEmpty {
                    Text("Ride \(entry.rideId.prefix(8))…")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(entry.rideFrom)")
                        .font(.subheadline).fontWeight(.semibold)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("\(entry.rideTo)")
                        .font(.subheadline).fontWeight(.semibold)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }

            // Coins row
            HStack(spacing: 16) {
                Label("Your bid: \(entry.bid.bidCoins) coins", systemImage: "circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                if entry.rideCoins > 0 {
                    Text("Rider offered: \(entry.rideCoins)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Status chip
            statusRow

            // Message
            if let msg = entry.bid.message, !msg.isEmpty {
                Text("\u{201C}\(msg)\u{201D}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            // Actions
            actionButtons
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        .sheet(isPresented: $showingEdit) {
            editBidPlaceholder
        }
        .alert("Error", isPresented: .constant(errorMsg != nil), actions: {
            Button("OK") { errorMsg = nil }
        }, message: {
            Text(errorMsg ?? "")
        })
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            let (color, icon): (Color, String) = {
                switch entry.bid.status {
                case .active:     return (.blue,   "clock")
                case .selected:   return (.green,  "checkmark.circle.fill")
                case .rejected:   return (.red,    "xmark.circle")
                case .withdrawn:  return (.gray,   "minus.circle")
                case .expired:    return (.orange, "clock.badge.xmark")
                case .autoClosed: return (.purple, "xmark.circle.fill")
                }
            }()
            Image(systemName: icon).foregroundStyle(color)
            Text(entry.bid.status.displayLabel)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(color)
            Spacer()
            Text(entry.bid.timeAgo)
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch entry.bid.status {
        case .active:
            HStack(spacing: 12) {
                Button {
                    showingEdit = true
                } label: {
                    Label("Edit Bid", systemImage: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                Button {
                    withdrawBid()
                } label: {
                    Group {
                        if isWorking {
                            ProgressView()
                        } else {
                            Label("Withdraw", systemImage: "xmark")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(isWorking)
            }
            .buttonStyle(.plain)

        case .selected:
            Label("Rider chose you! Check your active ride.", systemImage: "star.fill")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)

        default:
            EmptyView()
        }
    }

    // Placeholder — in a real implementation this would present PlaceBidSheet with the existing bid
    private var editBidPlaceholder: some View {
        Text("Edit bid for ride \(entry.rideId.prefix(8))…")
            .padding()
    }

    private func withdrawBid() {
        isWorking = true
        let rideId = entry.rideId
        let bidId  = entry.bid.id
        Task {
            do {
                // Build a minimal Ride-like object just to call withdrawBid
                let db = Firestore.firestore()
                let _ = db.collection("rides").document(rideId) // verify path
                // We call withdrawBid directly using Firestore path
                let now = Timestamp(date: Date())
                try await db.collection("rides").document(rideId)
                    .collection("bids").document(bidId)
                    .updateData(["status": "withdrawn", "updatedAt": now])
                try? await db.collection("rides").document(rideId)
                    .updateData(["bidCount": FieldValue.increment(Int64(-1))])
            } catch {
                await MainActor.run { errorMsg = error.localizedDescription }
            }
            await MainActor.run { isWorking = false }
        }
    }
}
