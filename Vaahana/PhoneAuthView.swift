//
//  PhoneAuthView.swift
//  Vaahana
//

import SwiftUI
import FirebaseAuth

// MARK: - Auth UI Delegate (needed for reCAPTCHA fallback on simulator)

private class PhoneVerificationUIDelegate: NSObject, AuthUIDelegate {
    private var rootVC: UIViewController? {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.rootViewController
    }

    func present(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)?) {
        rootVC?.present(viewControllerToPresent, animated: animated, completion: completion)
    }

    func dismiss(animated: Bool, completion: (() -> Void)?) {
        // Only dismiss what we presented — never dismiss the root hosting controller
        guard let presented = rootVC?.presentedViewController else {
            completion?()
            return
        }
        presented.dismiss(animated: animated, completion: completion)
    }
}

// Kept alive for the app's lifetime — avoids deallocation during async phone verification
private let sharedPhoneAuthUIDelegate = PhoneVerificationUIDelegate()

// MARK: - Phone Auth View

struct PhoneAuthView: View {
    @State private var countryCode = "+1"
    @State private var phoneNumber = ""
    @State private var verificationID: String?
    @State private var otpCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    let countryCodes = [
        ("🇺🇸", "+1"),
        ("🇮🇳", "+91"),
        ("🇬🇧", "+44"),
        ("🇦🇺", "+61"),
        ("🇦🇪", "+971")
    ]

    var body: some View {
        if verificationID == nil {
            phoneEntryView
        } else {
            otpEntryView
        }
    }

    // MARK: - Phone Entry Screen

    private var phoneEntryView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Text("Vaahana")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                    Text("Enter your phone number to continue.\nYou'll receive a one-time code.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Phone input
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Picker("Country", selection: $countryCode) {
                            ForEach(countryCodes, id: \.1) { flag, code in
                                Text("\(flag) \(code)").tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)

                        TextField("Phone number", text: $phoneNumber)
                            .keyboardType(.numberPad)
                            .font(.title3)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal)

                // Send code button
                Button {
                    sendCode()
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Send Code")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(phoneNumber.count >= 6 ? Color.black : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(phoneNumber.count < 6 || isLoading)
                .padding(.horizontal)
            }

            Spacer()

            Text("Your number is only used to identify you.\nWe don't share it with anyone.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - OTP Entry Screen

    private var otpEntryView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Text("Vaahana")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                    Text("Enter the 6-digit code sent to\n\(countryCode) \(phoneNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // OTP input
                VStack(spacing: 12) {
                    TextField("· · · · · ·", text: $otpCode)
                        .keyboardType(.numberPad)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .onChange(of: otpCode) { _, newValue in
                            // Enforce max 6 digits
                            if newValue.count > 6 {
                                otpCode = String(newValue.prefix(6))
                            }
                            // Auto-verify when 6 digits entered
                            if otpCode.count == 6 {
                                verifyCode()
                            }
                        }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                // Verify button
                Button {
                    verifyCode()
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Verify")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(otpCode.count == 6 ? Color.black : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(otpCode.count != 6 || isLoading)
                .padding(.horizontal)

                Button("Wrong number? Go back") {
                    verificationID = nil
                    otpCode = ""
                    errorMessage = nil
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Actions

    private func sendCode() {
        isLoading = true
        errorMessage = nil
        let fullNumber = "\(countryCode)\(phoneNumber)"

        PhoneAuthProvider.provider().verifyPhoneNumber(fullNumber, uiDelegate: sharedPhoneAuthUIDelegate) { id, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error {
                    errorMessage = error.localizedDescription
                    return
                }
                verificationID = id
            }
        }
    }

    private func verifyCode() {
        guard let verificationID else { return }
        isLoading = true
        errorMessage = nil

        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: otpCode
        )

        Auth.auth().signIn(with: credential) { _, error in
            DispatchQueue.main.async {
                isLoading = false
                if error != nil {
                    errorMessage = "Invalid code. Please try again."
                    otpCode = ""
                    return
                }
                // AuthState listener in VaahanaApp automatically navigates to ContentView
            }
        }
    }
}
