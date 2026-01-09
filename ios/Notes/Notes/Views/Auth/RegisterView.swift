import SwiftUI

struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authService = AuthService.shared
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    private var passwordsMatch: Bool {
        password == confirmPassword
    }

    private var canSubmit: Bool {
        !username.isEmpty &&
        !password.isEmpty &&
        passwordsMatch &&
        password.count >= 12 &&
        !authService.isLoading
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(.primary)

                Text("Create Account")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Sign up to get started")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Form
            VStack(spacing: 16) {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)

                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)

                // Validation messages
                VStack(spacing: 4) {
                    if !password.isEmpty && password.count < 12 {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text("Password must be at least 12 characters")
                            Spacer()
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }

                    if !confirmPassword.isEmpty && !passwordsMatch {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text("Passwords do not match")
                            Spacer()
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }

                    if let error = authService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }

                Button {
                    Task {
                        try? await authService.register(username: username, password: password)
                    }
                } label: {
                    Group {
                        if authService.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Create Account")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, 32)

            Spacer()

            // Back to login
            HStack {
                Text("Already have an account?")
                    .foregroundStyle(.secondary)
                Button("Sign In") {
                    authService.clearError()
                    dismiss()
                }
            }
            .font(.subheadline)
            .padding(.bottom, 32)
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    authService.clearError()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RegisterView()
    }
}
