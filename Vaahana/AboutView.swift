//
//  AboutView.swift
//  Vaahana
//

import SwiftUI

struct AboutView: View {
    private let appVersion: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }()

    var body: some View {
        List {
            // ── Header ──────────────────────────────────────────
            Section {
                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.blue.gradient)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Text("V")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        )
                    Text("Vaahana")
                        .font(.title2).fontWeight(.bold)
                    Text("Rides between neighbors")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowBackground(Color.clear)
            }

            // ── Website ─────────────────────────────────────────
            Section {
                linkRow(
                    icon: "globe",
                    tint: .blue,
                    title: "Website",
                    subtitle: "vaahana.app",
                    url: "https://vaahana.app"
                )
                linkRow(
                    icon: "info.circle",
                    tint: .indigo,
                    title: "How it works",
                    subtitle: "Learn about community carpooling",
                    url: "https://vaahana.app/#how"
                )
            } header: {
                Text("Vaahana")
            }

            // ── Contact ─────────────────────────────────────────
            Section {
                linkRow(
                    icon: "envelope",
                    tint: .blue,
                    title: "General",
                    subtitle: "hello@vaahana.app",
                    url: "mailto:hello@vaahana.app"
                )
                linkRow(
                    icon: "lifepreserver",
                    tint: .green,
                    title: "Help & Support",
                    subtitle: "help@vaahana.app",
                    url: "mailto:help@vaahana.app"
                )
                linkRow(
                    icon: "shield",
                    tint: .orange,
                    title: "Safety",
                    subtitle: "safety@vaahana.app",
                    url: "mailto:safety@vaahana.app"
                )
            } header: {
                Text("Contact")
            } footer: {
                Text("We read every message and respond within one business day.")
            }

            // ── Legal ────────────────────────────────────────────
            Section {
                linkRow(
                    icon: "lock.shield",
                    tint: .secondary,
                    title: "Privacy Policy",
                    subtitle: nil,
                    url: "mailto:privacy@vaahana.app"
                )
                linkRow(
                    icon: "doc.text",
                    tint: .secondary,
                    title: "Terms of Service",
                    subtitle: nil,
                    url: "mailto:legal@vaahana.app"
                )
            } header: {
                Text("Legal")
            } footer: {
                Text("© 2026 Vaahana. Built by the diaspora, for the diaspora.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func linkRow(icon: String, tint: Color, title: String, subtitle: String?, url: String) -> some View {
        if let dest = URL(string: url) {
            Link(destination: dest) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.15))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(tint)
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.body)
                            .foregroundStyle(.primary)
                        if let sub = subtitle {
                            Text(sub)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
