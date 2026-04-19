//
//  AuthFlow.swift
//  Vaahana
//
//  Landing → Sign Up → Email Verification Pending → (signed in)
//  Landing → Login
//  Login   → Forgot Password

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Auth Flow Root

struct AuthFlowView: View {
    enum Screen {
        case landing
        case signUp
        case verifyEmail
        case login
        case forgotPassword
    }

    @State private var screen: Screen = .landing

    var body: some View {
        switch screen {
        case .landing:        LandingView(screen: $screen)
        case .signUp:         SignUpView(screen: $screen)
        case .verifyEmail:    VerifyEmailView(screen: $screen)
        case .login:          LoginView(screen: $screen)
        case .forgotPassword: ForgotPasswordView(screen: $screen)
        }
    }
}

// MARK: - Landing

struct LandingView: View {
    @Binding var screen: AuthFlowView.Screen

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Image("Vaahana Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

                Text("Vaahana")
                    .font(.system(size: 44, weight: .black, design: .rounded))

                Text("Rides, sorted.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 12) {
                AuthButton(title: "Create Account", style: .primary) {
                    screen = .signUp
                }
                AuthButton(title: "Sign In", style: .secondary) {
                    screen = .login
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - Sign Up

struct SignUpView: View {
    @Binding var screen: AuthFlowView.Screen

    @State private var name            = ""
    @State private var email           = ""
    @State private var phone           = ""
    @State private var password        = ""
    @State private var confirmPassword = ""
    @State private var isLoading       = false
    @State private var errorMessage: String?

    private let functions = Functions.functions()

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && email.contains("@") && email.contains(".")
            && phone.count >= 7
            && password.count >= 6
            && password == confirmPassword
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text("Create Account")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("A verification link will be sent to your email.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                VStack(spacing: 12) {
                    InputField(label: "Full Name", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()

                    InputField(label: "Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)

                    InputField(label: "Phone / WhatsApp", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)

                    InputField(label: "Password (min 6 chars)", text: $password, isSecure: true)
                        .textContentType(.newPassword)

                    InputField(label: "Confirm Password", text: $confirmPassword, isSecure: true)
                        .textContentType(.newPassword)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                AuthButton(
                    title: "Create Account",
                    style: .primary,
                    isLoading: isLoading,
                    isDisabled: !isValid
                ) { createAccount() }

                Button { screen = .login } label: {
                    Text("Already have an account? **Sign In**")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 24)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func createAccount() {
        isLoading = true
        errorMessage = nil

        let callable = functions.httpsCallable("checkPhoneUnique")
        callable.call(["phone": phone.trimmingCharacters(in: .whitespaces)]) { _, error in
            if let error {
                DispatchQueue.main.async {
                    isLoading = false
                    errorMessage = Self.callableError(error)
                }
                return
            }
            // Phone is unique — create Firebase Auth account
            Auth.auth().createUser(
                withEmail: email.lowercased().trimmingCharacters(in: .whitespaces),
                password: password
            ) { result, error in
                if let error {
                    DispatchQueue.main.async {
                        isLoading = false
                        errorMessage = Self.authError(error)
                    }
                    return
                }
                guard let user = result?.user else { return }

                // Save profile name
                let change = user.createProfileChangeRequest()
                change.displayName = name.trimmingCharacters(in: .whitespaces)
                change.commitChanges(completion: nil)

                // Save Firestore doc
                let db = FirestoreService.shared
                db.collection("users").document(user.uid).setData([
                    "displayName": name.trimmingCharacters(in: .whitespaces),
                    "phone":       phone.trimmingCharacters(in: .whitespaces),
                    "whatsapp":    phone.trimmingCharacters(in: .whitespaces),
                    "role":        "rider",
                    "coins":       100,
                    "coinsLocked": 0,
                    "isAdmin":     false,
                ], merge: true)

                // Send Firebase verification email
                user.sendEmailVerification { _ in
                    DispatchQueue.main.async {
                        isLoading = false
                        screen = .verifyEmail
                    }
                }
            }
        }
    }

    static func callableError(_ error: Error) -> String {
        (error as NSError).userInfo["NSLocalizedDescription"] as? String
            ?? error.localizedDescription
    }

    static func authError(_ error: Error) -> String {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .emailAlreadyInUse: return "An account with this email already exists. Please sign in."
        case .invalidEmail:      return "Please enter a valid email address."
        case .weakPassword:      return "Password is too weak. Use at least 6 characters."
        default:                 return error.localizedDescription
        }
    }
}

// MARK: - Verify Email

struct VerifyEmailView: View {
    @Binding var screen: AuthFlowView.Screen

    @State private var isChecking  = false
    @State private var isResending = false
    @State private var errorMessage: String?
    @State private var resendCountdown = 0

    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)

                Text("Verify your email")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                if let email = Auth.auth().currentUser?.email {
                    Text("We sent a verification link to\n**\(email)**\n\nTap the link in that email, then come back here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                AuthButton(title: "I've verified — Continue", style: .primary, isLoading: isChecking) {
                    checkVerification()
                }

                Button { resendEmail() } label: {
                    if resendCountdown > 0 {
                        Text("Resend in \(resendCountdown)s")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if isResending {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Resend verification email")
                            .font(.footnote).foregroundStyle(.blue)
                    }
                }
                .disabled(resendCountdown > 0 || isResending)

                Button {
                    try? Auth.auth().signOut()
                    screen = .landing
                } label: {
                    Text("Use a different email")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color(UIColor.systemGroupedBackground))
        .onReceive(timer) { _ in
            // Auto-check every 4 seconds in the background
            Auth.auth().currentUser?.reload { _ in }
        }
    }

    private func checkVerification() {
        isChecking = true
        errorMessage = nil
        Auth.auth().currentUser?.reload { error in
            DispatchQueue.main.async {
                isChecking = false
                if let error {
                    errorMessage = error.localizedDescription
                    return
                }
                if Auth.auth().currentUser?.isEmailVerified == true {
                    // Auth state listener in UserState handles navigation
                } else {
                    errorMessage = "Email not verified yet. Check your inbox (and spam folder)."
                }
            }
        }
    }

    private func resendEmail() {
        isResending = true
        Auth.auth().currentUser?.sendEmailVerification { error in
            DispatchQueue.main.async {
                isResending = false
                if let error {
                    errorMessage = error.localizedDescription
                } else {
                    startCountdown()
                }
            }
        }
    }

    private func startCountdown() {
        resendCountdown = 60
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            resendCountdown -= 1
            if resendCountdown <= 0 { t.invalidate() }
        }
    }
}

// MARK: - Login

struct LoginView: View {
    @Binding var screen: AuthFlowView.Screen

    @State private var email       = ""
    @State private var password    = ""
    @State private var isLoading   = false
    @State private var errorMessage: String?

    private var isValid: Bool { email.contains("@") && password.count >= 6 }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text("Welcome back")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Sign in to your Vaahana account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                VStack(spacing: 12) {
                    InputField(label: "Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)

                    InputField(label: "Password", text: $password, isSecure: true)
                        .textContentType(.password)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                AuthButton(
                    title: "Sign In",
                    style: .primary,
                    isLoading: isLoading,
                    isDisabled: !isValid
                ) { signIn() }

                Button { screen = .forgotPassword } label: {
                    Text("Forgot Password?")
                        .font(.footnote).foregroundStyle(.blue)
                }

                Button { screen = .signUp } label: {
                    Text("Don't have an account? **Create one**")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 24)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func signIn() {
        isLoading = true
        errorMessage = nil

        Auth.auth().signIn(
            withEmail: email.lowercased().trimmingCharacters(in: .whitespaces),
            password: password
        ) { result, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error {
                    errorMessage = SignUpView.authError(error)
                    return
                }
                // If email not verified, show the verify screen
                if result?.user.isEmailVerified == false {
                    screen = .verifyEmail
                }
                // Otherwise auth state listener in UserState handles navigation
            }
        }
    }
}

// MARK: - Forgot Password

struct ForgotPasswordView: View {
    @Binding var screen: AuthFlowView.Screen

    @State private var email      = ""
    @State private var isSending  = false
    @State private var sent       = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 52))
                    .foregroundStyle(.orange)

                Text("Reset Password")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Enter your email and we'll send you a reset link.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if sent {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("Reset email sent to **\(email)**.\nCheck your inbox.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                AuthButton(title: "Back to Sign In", style: .primary) {
                    screen = .login
                }
            } else {
                VStack(spacing: 14) {
                    InputField(label: "Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let error = errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    AuthButton(
                        title: "Send Reset Email",
                        style: .primary,
                        isLoading: isSending,
                        isDisabled: !email.contains("@")
                    ) { sendReset() }

                    Button { screen = .login } label: {
                        Text("Back to Sign In")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func sendReset() {
        isSending = true
        errorMessage = nil
        Auth.auth().sendPasswordReset(
            withEmail: email.lowercased().trimmingCharacters(in: .whitespaces)
        ) { error in
            DispatchQueue.main.async {
                isSending = false
                if let error { errorMessage = error.localizedDescription }
                else { sent = true }
            }
        }
    }
}

// MARK: - Shared Components

struct AuthButton: View {
    enum Style { case primary, secondary }

    let title: String
    var style: Style = .primary
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(style == .primary ? .white : .primary)
                } else {
                    Text(title).font(.headline)
                }
            }
            .foregroundStyle(style == .primary ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(buttonBackground)
            .cornerRadius(14)
        }
        .disabled(isDisabled || isLoading)
    }

    private var buttonBackground: Color {
        if isDisabled || isLoading {
            return style == .primary ? .gray : Color(UIColor.secondarySystemGroupedBackground)
        }
        return style == .primary ? .black : Color(UIColor.secondarySystemGroupedBackground)
    }
}

struct InputField: View {
    let label: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(label, text: $text)
            } else {
                TextField(label, text: $text)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Firestore shorthand

private enum FirestoreService {
    static var shared: Firestore { Firestore.firestore() }
}
