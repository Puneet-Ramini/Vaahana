//
//  AuthView.swift
//  Vaahana
//

import SwiftUI
import FirebaseAuth

struct AuthView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var isValid: Bool {
        email.contains("@") && password.count >= 6
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Text("Vaahana")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                    Text("Sign in to continue")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Fields
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)

                    SecureField("Password", text: $password)
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal)

                // Sign in / create account button
                Button {
                    signIn()
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Continue")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValid ? Color.black : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(!isValid || isLoading)
                .padding(.horizontal)
            }

            Spacer()

            Text("New users are registered automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func signIn() {
        isLoading = true
        errorMessage = nil

        // Try signing in first; if the account doesn't exist, create it
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            if result != nil {
                isLoading = false
                return // AuthState listener handles navigation
            }

            // Sign-in failed — attempt account creation
            Auth.auth().createUser(withEmail: email, password: password) { _, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if let error {
                        errorMessage = error.localizedDescription
                    }
                    // On success, AuthState listener handles navigation
                }
            }
        }
    }
}
