//
//  VaahanaApp.swift
//  Vaahana
//
//  Created by Puneet Ramini on 4/6/26.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct VaahanaApp: App {
    init() {
        FirebaseApp.configure()
        // Silently sign in anonymously — no UI, no personal data collected
        if Auth.auth().currentUser == nil {
            Auth.auth().signInAnonymously { _, _ in }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
