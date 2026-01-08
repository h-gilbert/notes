import SwiftUI

struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authService = AuthService.shared

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showingSuccess = false
    @State private var errorMessage: String?

    private var isFormValid: Bool {
        !currentPassword.isEmpty &&
        newPassword.count >= 6 &&
        newPassword == confirmPassword
    }

    private var passwordsMatch: Bool {
        confirmPassword.isEmpty || newPassword == confirmPassword
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current Password", text: $currentPassword)
                        .textContentType(.password)
                } header: {
                    Text("Current Password")
                }

                Section {
                    SecureField("New Password", text: $newPassword)
                        .textContentType(.newPassword)

                    SecureField("Confirm New Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                } header: {
                    Text("New Password")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if newPassword.count > 0 && newPassword.count < 6 {
                            Text("Password must be at least 6 characters")
                                .foregroundColor(.orange)
                        }
                        if !passwordsMatch {
                            Text("Passwords do not match")
                                .foregroundColor(.red)
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button {
                        Task {
                            await changePassword()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if authService.isLoading {
                                ProgressView()
                            } else {
                                Text("Change Password")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!isFormValid || authService.isLoading)
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Password Changed", isPresented: $showingSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your password has been changed successfully.")
            }
        }
    }

    private func changePassword() async {
        errorMessage = nil

        do {
            try await authService.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            showingSuccess = true
        } catch let error as AuthError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Failed to change password: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ChangePasswordView()
}
