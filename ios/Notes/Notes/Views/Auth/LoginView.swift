import SwiftUI

struct LoginView: View {
    @State private var authService = AuthService.shared
    @State private var username = ""
    @State private var password = ""
    @State private var showingRegister = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 60))
                        .foregroundStyle(.primary)

                    Text("Notes")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Sign in to sync your notes")
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
                        .textContentType(.password)

                    if let error = authService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task {
                            try? await authService.login(username: username, password: password)
                        }
                    } label: {
                        Group {
                            if authService.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Sign In")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(username.isEmpty || password.isEmpty || authService.isLoading)
                }
                .padding(.horizontal, 32)

                Spacer()

                // Register link
                HStack {
                    Text("Don't have an account?")
                        .foregroundStyle(.secondary)
                    Button("Sign Up") {
                        authService.clearError()
                        showingRegister = true
                    }
                }
                .font(.subheadline)
                .padding(.bottom, 32)
            }
            .navigationDestination(isPresented: $showingRegister) {
                RegisterView()
            }
        }
    }
}

#Preview {
    LoginView()
}
