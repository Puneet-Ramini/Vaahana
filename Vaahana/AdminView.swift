//
//  AdminView.swift
//  Vaahana
//
//  Admin-only dashboard. Gated by isAdmin == true on the Firestore user doc.
//  Shows reconciliation logs, lets admins inspect/repair users and rides.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - ReconciliationLog model

struct ReconciliationLog: Identifiable {
    let id: String
    let entityType: String
    let entityId: String
    let severity: String
    let issueCode: String
    let actionTaken: String
    let detectedAt: Date

    var severityColor: Color {
        switch severity {
        case "critical": return .red
        case "error":    return .orange
        case "warning":  return .yellow
        default:         return .secondary
        }
    }
}

// MARK: - AdminView

struct AdminView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                LogsTab()
                    .tabItem { Label("Logs", systemImage: "doc.text.magnifyingglass") }
                    .tag(0)

                UserInspectorTab()
                    .tabItem { Label("Users", systemImage: "person.2.fill") }
                    .tag(1)

                RideInspectorTab()
                    .tabItem { Label("Rides", systemImage: "car.fill") }
                    .tag(2)
            }
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Logs Tab

private struct LogsTab: View {
    @State private var logs: [ReconciliationLog] = []
    @State private var isLoading = true
    @State private var filterSeverity = "all"

    private let db = Firestore.firestore()
    private let severities = ["all", "critical", "error", "warning", "info"]

    var filteredLogs: [ReconciliationLog] {
        if filterSeverity == "all" { return logs }
        return logs.filter { $0.severity == filterSeverity }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Severity filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(severities, id: \.self) { sev in
                        Button(sev.capitalized) {
                            filterSeverity = sev
                        }
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(filterSeverity == sev ? Color.black : Color(UIColor.secondarySystemGroupedBackground))
                        .foregroundStyle(filterSeverity == sev ? .white : .primary)
                        .cornerRadius(20)
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
            Divider()

            if isLoading {
                ProgressView("Loading logs…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredLogs.isEmpty {
                ContentUnavailableView("No Logs", systemImage: "checkmark.seal", description: Text("No reconciliation issues found."))
            } else {
                List(filteredLogs) { log in
                    LogRow(log: log)
                }
                .listStyle(.plain)
            }
        }
        .task { await loadLogs() }
        .refreshable { await loadLogs() }
    }

    private func loadLogs() async {
        isLoading = true
        let snap = try? await db.collection("reconciliationLogs")
            .order(by: "detectedAt", descending: true)
            .limit(to: 200)
            .getDocuments()
        logs = snap?.documents.compactMap { doc -> ReconciliationLog? in
            let d = doc.data()
            guard let detectedAt = (d["detectedAt"] as? Timestamp)?.dateValue() else { return nil }
            return ReconciliationLog(
                id: doc.documentID,
                entityType:  d["entityType"]  as? String ?? "",
                entityId:    d["entityId"]    as? String ?? "",
                severity:    d["severity"]    as? String ?? "info",
                issueCode:   d["issueCode"]   as? String ?? "",
                actionTaken: d["actionTaken"] as? String ?? "",
                detectedAt:  detectedAt
            )
        } ?? []
        isLoading = false
    }
}

private struct LogRow: View {
    let log: ReconciliationLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(log.severityColor).frame(width: 8, height: 8)
                Text(log.issueCode)
                    .font(.caption).fontWeight(.semibold)
                Spacer()
                Text(log.detectedAt, style: .relative)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(log.entityType.capitalized + ": " + log.entityId)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(log.actionTaken)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - User Inspector Tab

private struct UserInspectorTab: View {
    @State private var uidInput = ""
    @State private var userData: [String: Any]?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var adjustAmount = ""
    @State private var isAdjusting = false
    @State private var adjustMessage: String?

    private let db = Firestore.firestore()

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("User UID", text: $uidInput)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    Button("Lookup") { Task { await lookup() } }
                        .disabled(uidInput.isEmpty || isLoading)
                }
            } header: {
                Text("User Lookup")
            }

            if isLoading {
                Section { ProgressView() }
            } else if let error = errorMessage {
                Section { Text(error).foregroundStyle(.red).font(.caption) }
            } else if let data = userData {
                Section("Profile") {
                    infoRow("Name",  data["displayName"] as? String ?? "—")
                    infoRow("Phone", data["phone"] as? String ?? "—")
                    infoRow("Role",  data["role"]  as? String ?? "—")
                    infoRow("Email", data["email"] as? String ?? "—")
                    if let admin = data["isAdmin"] as? Bool, admin {
                        infoRow("Admin", "Yes")
                    }
                }

                Section("Coins") {
                    infoRow("Balance",     "\(data["coins"]       as? Int ?? 0)")
                    infoRow("Locked",      "\(data["coinsLocked"] as? Int ?? 0)")
                    infoRow("Last Grant",  data["lastDailyCoinDate"] as? String ?? "—")
                    infoRow("Active Ride", data["activeRideId"] as? String ?? "—")
                }

                Section("Adjust Balance") {
                    HStack {
                        TextField("±amount (e.g. 50 or -20)", text: $adjustAmount)
                            .keyboardType(.numbersAndPunctuation)
                        Button("Apply") { Task { await adjustCoins() } }
                            .disabled(adjustAmount.isEmpty || isAdjusting)
                    }
                    if let msg = adjustMessage {
                        Text(msg).font(.caption).foregroundStyle(.green)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).lineLimit(1)
        }
    }

    private func lookup() async {
        isLoading = true
        errorMessage = nil
        userData = nil
        let doc = try? await db.collection("users").document(uidInput.trimmingCharacters(in: .whitespaces)).getDocument()
        isLoading = false
        if let data = doc?.data(), !data.isEmpty {
            userData = data
        } else {
            errorMessage = "User not found."
        }
    }

    private func adjustCoins() async {
        guard let amount = Int(adjustAmount.trimmingCharacters(in: .whitespaces)) else { return }
        isAdjusting = true
        adjustMessage = nil
        let uid = uidInput.trimmingCharacters(in: .whitespaces)
        do {
            try await db.collection("users").document(uid).updateData([
                "coins": FieldValue.increment(Int64(amount))
            ])
            adjustMessage = "Adjusted by \(amount > 0 ? "+" : "")\(amount) coins."
            adjustAmount = ""
            await lookup()
        } catch {
            adjustMessage = "Error: \(error.localizedDescription)"
        }
        isAdjusting = false
    }
}

// MARK: - Ride Inspector Tab

private struct RideInspectorTab: View {
    @State private var rideIdInput = ""
    @State private var rideData: [String: Any]?
    @State private var bidsData: [[String: Any]] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let db = Firestore.firestore()

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Ride UUID", text: $rideIdInput)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    Button("Lookup") { Task { await lookupRide() } }
                        .disabled(rideIdInput.isEmpty || isLoading)
                }
            } header: {
                Text("Ride Inspector")
            }

            if isLoading {
                Section { ProgressView() }
            } else if let error = errorMessage {
                Section { Text(error).foregroundStyle(.red).font(.caption) }
            } else if let data = rideData {
                Section("Core") {
                    infoRow("Status",   data["status"]   as? String ?? "—")
                    infoRow("Rider",    data["riderId"]  as? String ?? "—")
                    infoRow("Driver",   data["driverId"] as? String ?? "—")
                    infoRow("From",     data["from"]     as? String ?? "—")
                    infoRow("To",       data["to"]       as? String ?? "—")
                }
                Section("Coins") {
                    infoRow("Offered",     "\(data["coins"]            as? Int ?? 0)")
                    infoRow("Final",       "\(data["finalCoins"]       as? Int ?? 0)")
                    infoRow("Locked",      "\(data["coinsLocked"]      as? Int ?? 0)")
                    infoRow("Transferred", "\(data["coinsTransferred"] as? Int ?? 0)")
                    infoRow("CoinStatus",  data["coinStatus"] as? String ?? "—")
                }
                if !bidsData.isEmpty {
                    Section("Bids (\(bidsData.count))") {
                        ForEach(Array(bidsData.enumerated()), id: \.offset) { _, bid in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bid["driverName"] as? String ?? "Driver")
                                    .font(.subheadline).fontWeight(.medium)
                                HStack {
                                    Text("\(bid["bidCoins"] as? Int ?? 0) coins")
                                    Spacer()
                                    Text(bid["status"] as? String ?? "")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        Task { await cancelRide() }
                    } label: {
                        Label("Force Cancel Ride", systemImage: "xmark.circle")
                    }
                    .disabled((data["status"] as? String).map { ["completed","cancelled","expired"].contains($0) } ?? true)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).lineLimit(1)
        }
    }

    private func lookupRide() async {
        isLoading = true
        errorMessage = nil
        rideData = nil
        bidsData = []
        let trimmed = rideIdInput.trimmingCharacters(in: .whitespaces)
        let doc = try? await db.collection("rides").document(trimmed).getDocument()
        if let data = doc?.data(), !data.isEmpty {
            rideData = data
            let bidsSnap = try? await db.collection("rides").document(trimmed).collection("bids").getDocuments()
            bidsData = bidsSnap?.documents.map { $0.data() } ?? []
        } else {
            errorMessage = "Ride not found."
        }
        isLoading = false
    }

    private func cancelRide() async {
        let trimmed = rideIdInput.trimmingCharacters(in: .whitespaces)
        try? await db.collection("rides").document(trimmed).updateData([
            "status":       "cancelled",
            "cancelledBy":  Auth.auth().currentUser?.uid ?? "admin",
            "cancellationReasonCode": "admin_force_cancel",
            "updatedAt":    FieldValue.serverTimestamp(),
        ])
        await lookupRide()
    }
}
