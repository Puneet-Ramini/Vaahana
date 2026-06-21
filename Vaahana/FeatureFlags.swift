//
//  FeatureFlags.swift
//  Vaahana
//
//  Compile-time feature switches. Set to true to re-enable for a release.
//

enum FeatureFlags {
    /// Show WhatsApp-sourced rides in the feed and surface WhatsApp contact CTAs.
    static let whatsappEnabled = false

    /// Prompt users to rate each other after a completed ride.
    static let ratingsEnabled = false
}
