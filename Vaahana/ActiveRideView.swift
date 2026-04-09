//
//  ActiveRideView.swift
//  Vaahana
//
//  Unified active-ride screen for both rider and driver.
//  Shows status-driven action buttons and contact info.
//

import SwiftUI
import FirebaseAuth

struct ActiveRideView: View {
    let ride: Ride
    let role: UserRole

    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showCancelConfirm = false

    private var uid: String { Auth.auth().currentUser?.uid ?? "" }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusBanner
                    routeCard
                    contactCard
                    actionSection

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Active Ride")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        let text  = role == .rider ? ride.status.riderDisplayText : ride.status.driverDisplayText
        let color = statusColor(for: ride.status)
        return HStack(spacing: 10) {
            Image(systemName: statusIcon(for: ride.status))
                .font(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text("Status").font(.caption).foregroundStyle(.secondary)
                Text(text).font(.headline).foregroundStyle(color)
            }
            Spacer()
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(14)
    }

    // MARK: - Route Card

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From").font(.caption).foregroundStyle(.secondary)
                    Text(ride.from).font(.headline).lineLimit(1)
                }
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("To").font(.caption).foregroundStyle(.secondary)
                    Text(ride.to).font(.headline).lineLimit(1)
                }
            }
            Divider()
            HStack {
                Label(ride.pickupDateFormatted, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("🪙 \(ride.coins)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Contact Card

    @ViewBuilder
    private var contactCard: some View {
        if role == .rider, let driverName = ride.driverName {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Driver").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    avatarCircle(initials: nameInitials(driverName), color: .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(driverName).font(.headline)
                        if let ph = ride.driverPhone { Text(ph).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if let wa = ride.driverWhatsapp {
                        whatsAppButton(name: driverName, phone: wa)
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(14)

        } else if role == .driver {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Rider").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    avatarCircle(initials: ride.initials, color: .black)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ride.name).font(.headline)
                        Text(ride.phone).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    whatsAppButton(name: ride.name, phone: ride.whatsappPhone)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(14)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionSection: some View {
        VStack(spacing: 12) {
            if role == .driver {
                driverActions
            } else {
                riderActions
            }
        }
    }

    @ViewBuilder
    private var driverActions: some View {
        switch ride.status {
        case .accepted:
            primaryButton("I'm On My Way", icon: "car.fill", color: .orange) {
                await run { try await RideService.shared.updateRideStatus(ride, to: .driverEnroute) }
            }
            cancelButton
        case .driverEnroute:
            primaryButton("I've Arrived", icon: "mappin.circle.fill", color: .orange) {
                await run { try await RideService.shared.updateRideStatus(ride, to: .driverArrived) }
            }
            cancelButton
        case .driverArrived:
            primaryButton("Start Ride", icon: "play.circle.fill", color: .green) {
                await run { try await RideService.shared.updateRideStatus(ride, to: .rideStarted) }
            }
        case .rideStarted:
            primaryButton("Complete Ride", icon: "checkmark.circle.fill", color: .green) {
                await run { try await RideService.shared.completeRide(ride) }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var riderActions: some View {
        // Rider can only cancel before the ride starts
        if ride.status == .accepted || ride.status == .driverEnroute {
            cancelButton
        }
    }

    private var cancelButton: some View {
        Button { showCancelConfirm = true } label: {
            Text("Cancel Ride")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
        }
        .confirmationDialog("Cancel this ride?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Cancel Ride", role: .destructive) {
                Task { await run { try await RideService.shared.cancelRide(ride, cancelledBy: uid) } }
            }
        } message: {
            Text(ride.coinStatus == .locked
                 ? "Your \(ride.coinsLocked) locked coins will be refunded."
                 : "The ride will be cancelled.")
        }
    }

    // MARK: - Reusable Components

    private func primaryButton(_ title: String, icon: String, color: Color, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isProcessing ? Color.gray : color)
                .cornerRadius(12)
        }
        .disabled(isProcessing)
    }

    private func avatarCircle(initials: String, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 46, height: 46)
            .overlay {
                Text(initials)
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.white)
            }
    }

    private func whatsAppButton(name: String, phone: String) -> some View {
        Button {
            let msg = role == .driver
                ? "Hi \(name), I'm your Vaahana driver! I'm on my way."
                : "Hi \(name), just checking in about our Vaahana ride!"
            let encoded = msg.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let cleaned = phone.replacingOccurrences(of: " ", with: "")
            if let url = URL(string: "https://wa.me/\(cleaned)?text=\(encoded)") {
                UIApplication.shared.open(url)
            }
        } label: {
            Image(systemName: "message.fill")
                .font(.title2)
                .foregroundStyle(.green)
        }
    }

    // MARK: - Helpers

    private func run(_ action: () async throws -> Void) async {
        isProcessing = true
        errorMessage = nil
        do { try await action() }
        catch { errorMessage = error.localizedDescription }
        isProcessing = false
    }

    private func nameInitials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(name.prefix(2)).uppercased()
    }

    private func statusIcon(for status: RideStatus) -> String {
        switch status {
        case .accepted:      return "checkmark.circle.fill"
        case .driverEnroute: return "car.fill"
        case .driverArrived: return "mappin.circle.fill"
        case .rideStarted:   return "play.circle.fill"
        case .completed:     return "star.circle.fill"
        case .cancelled:     return "xmark.circle.fill"
        default:             return "clock.fill"
        }
    }

    private func statusColor(for status: RideStatus) -> Color {
        switch status {
        case .accepted:              return .blue
        case .driverEnroute,
             .driverArrived:        return .orange
        case .rideStarted:          return .green
        case .completed:            return .green
        case .cancelled, .expired:  return .red
        default:                    return .secondary
        }
    }
}
