import Foundation

// MARK: - Auth Models

struct AuthRequest: Codable, Sendable {
    let username: String
    let password: String
}

struct RefreshRequest: Codable, Sendable {
    let refresh_token: String
}

struct AuthResponse: Codable, Sendable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
    let token_type: String
    let user: UserDTO
}

struct ChangePasswordRequest: Codable, Sendable {
    let current_password: String
    let new_password: String
}

struct UserDTO: Codable, Sendable {
    let id: String
    let username: String
}

// MARK: - Auth Error

enum AuthError: Error, LocalizedError {
    case invalidCredentials
    case userExists
    case networkError(Error)
    case serverError(String)
    case invalidResponse
    case tokenExpired
    case passwordMismatch

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid username or password"
        case .userExists:
            return "Username already exists"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let message):
            return message
        case .invalidResponse:
            return "Invalid response from server"
        case .tokenExpired:
            return "Session expired. Please log in again."
        case .passwordMismatch:
            return "Current password is incorrect"
        }
    }
}

// MARK: - Auth Service

@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    private(set) var isAuthenticated = false
    private(set) var currentUser: UserDTO?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let baseURL: String
    private let session: URLSession

    // Token refresh settings - refresh 5 minutes before expiry
    private let tokenRefreshBuffer: TimeInterval = 5 * 60
    private var refreshTimer: Timer?
    private var tokenExpiresAt: Date?

    private init() {
        self.baseURL = Constants.API.baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        // Check for existing tokens in Keychain
        if let accessToken = KeychainHelper.getAccessToken() {
            Task {
                await initializeWithToken(accessToken)
            }
        }
    }

    private func initializeWithToken(_ token: String) async {
        if isTokenExpired(token) {
            // Access token expired, try to refresh using refresh token
            #if DEBUG
            print("AuthService: Access token expired, attempting refresh")
            #endif
            await refreshTokenIfNeeded()
            return
        }

        self.isAuthenticated = true
        self.tokenExpiresAt = getTokenExpirationDate(token)
        await configureAPIClient(token: token)

        // Check if token needs refresh soon
        if shouldRefreshToken(token) {
            #if DEBUG
            print("AuthService: Token expiring soon, refreshing...")
            #endif
            await refreshTokenIfNeeded()
        }

        // Schedule token refresh
        scheduleTokenRefresh()
    }

    // MARK: - Public Methods

    func login(username: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let request = AuthRequest(username: username, password: password)
        let response: AuthResponse = try await performRequest(
            endpoint: "/api/auth/login",
            method: "POST",
            body: request
        )

        await handleAuthSuccess(response: response)
    }

    func register(username: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let request = AuthRequest(username: username, password: password)
        let response: AuthResponse = try await performRequest(
            endpoint: "/api/auth/register",
            method: "POST",
            body: request
        )

        await handleAuthSuccess(response: response)
    }

    func logout() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        tokenExpiresAt = nil

        // Clear tokens from Keychain
        KeychainHelper.clearTokens()

        // Clear other stored data
        UserDefaults.standard.removeObject(forKey: Constants.Storage.lastSyncDateKey)

        isAuthenticated = false
        currentUser = nil

        Task {
            await APIClient.shared.setAuthToken(nil)
            // Disconnect WebSocket
            await WebSocketService.shared.disconnect()
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let token = KeychainHelper.getAccessToken() else {
            throw AuthError.tokenExpired
        }

        let request = ChangePasswordRequest(current_password: currentPassword, new_password: newPassword)
        try await performAuthenticatedRequest(
            endpoint: "/api/auth/change-password",
            method: "POST",
            body: request,
            token: token
        )
    }

    private func performAuthenticatedRequest<B: Encodable>(
        endpoint: String,
        method: String,
        body: B,
        token: String
    ) async throws {
        guard let url = URL(string: baseURL + endpoint) else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200, 201, 204:
                return // Success
            case 401:
                // Check if it's a password mismatch
                if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
                   let message = errorData["message"],
                   message.lowercased().contains("password") {
                    throw AuthError.passwordMismatch
                }
                throw AuthError.invalidCredentials
            default:
                if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
                   let message = errorData["message"] {
                    throw AuthError.serverError(message)
                }
                throw AuthError.serverError("Request failed with status \(httpResponse.statusCode)")
            }
        } catch let error as AuthError {
            self.errorMessage = error.localizedDescription
            throw error
        } catch {
            let authError = AuthError.networkError(error)
            self.errorMessage = authError.localizedDescription
            throw authError
        }
    }

    // MARK: - Token Refresh

    func refreshTokenIfNeeded() async {
        guard let refreshToken = KeychainHelper.getRefreshToken() else {
            #if DEBUG
            print("AuthService: No refresh token available")
            #endif
            logout()
            return
        }

        do {
            let request = RefreshRequest(refresh_token: refreshToken)
            let response: AuthResponse = try await performRequest(
                endpoint: "/api/auth/refresh",
                method: "POST",
                body: request
            )

            // Store new tokens in Keychain
            try KeychainHelper.saveTokens(
                accessToken: response.access_token,
                refreshToken: response.refresh_token
            )

            currentUser = response.user
            isAuthenticated = true
            tokenExpiresAt = Date().addingTimeInterval(TimeInterval(response.expires_in))

            // Update API client with new token
            await configureAPIClient(token: response.access_token)

            // Reconnect WebSocket with new token
            await WebSocketService.shared.disconnect()
            await WebSocketService.shared.connect(token: response.access_token)

            // Schedule next refresh
            scheduleTokenRefresh()

            #if DEBUG
            print("AuthService: Token refreshed successfully")
            #endif
        } catch {
            #if DEBUG
            print("AuthService: Failed to refresh token: \(error)")
            #endif
            // If refresh fails, logout the user
            logout()
        }
    }

    // MARK: - Private Methods

    private func handleAuthSuccess(response: AuthResponse) async {
        // Store tokens in Keychain
        do {
            try KeychainHelper.saveTokens(
                accessToken: response.access_token,
                refreshToken: response.refresh_token
            )
        } catch {
            #if DEBUG
            print("AuthService: Failed to save tokens to Keychain: \(error)")
            #endif
        }

        currentUser = response.user
        isAuthenticated = true
        tokenExpiresAt = Date().addingTimeInterval(TimeInterval(response.expires_in))

        await configureAPIClient(token: response.access_token)

        // Connect WebSocket for real-time updates
        await WebSocketService.shared.connect(token: response.access_token)

        // Schedule token refresh
        scheduleTokenRefresh()
    }

    private func configureAPIClient(token: String) async {
        await APIClient.shared.configure(baseURL: baseURL, authToken: token)
    }

    private func scheduleTokenRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        guard let expiresAt = tokenExpiresAt else { return }

        // Calculate when to refresh (5 minutes before expiry)
        let refreshTime = expiresAt.timeIntervalSinceNow - tokenRefreshBuffer

        guard refreshTime > 0 else {
            // Token already needs refresh
            Task {
                await refreshTokenIfNeeded()
            }
            return
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshTime, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshTokenIfNeeded()
            }
        }
    }

    // MARK: - Token Parsing

    private func isTokenExpired(_ token: String) -> Bool {
        guard let expirationDate = getTokenExpirationDate(token) else {
            return true // Assume expired if we can't parse
        }
        return expirationDate < Date()
    }

    private func shouldRefreshToken(_ token: String) -> Bool {
        guard let expirationDate = getTokenExpirationDate(token) else {
            return true // Refresh if we can't parse
        }
        let timeUntilExpiry = expirationDate.timeIntervalSince(Date())
        return timeUntilExpiry < tokenRefreshBuffer
    }

    private func getTokenExpirationDate(_ token: String) -> Date? {
        // JWT structure: header.payload.signature
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        // Decode the payload (second part)
        var payload = String(parts[1])
        // Handle base64url encoding
        payload = payload.replacingOccurrences(of: "-", with: "+")
        payload = payload.replacingOccurrences(of: "_", with: "/")
        // Add padding if needed for base64 decoding
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let payloadData = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return nil
        }

        return Date(timeIntervalSince1970: exp)
    }

    private func performRequest<T: Decodable, B: Encodable>(
        endpoint: String,
        method: String,
        body: B
    ) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200, 201:
                let decoded = try JSONDecoder().decode(T.self, from: data)
                return decoded
            case 401:
                throw AuthError.invalidCredentials
            case 409:
                throw AuthError.userExists
            default:
                if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
                   let message = errorData["message"] {
                    throw AuthError.serverError(message)
                }
                throw AuthError.serverError("Request failed with status \(httpResponse.statusCode)")
            }
        } catch let error as AuthError {
            self.errorMessage = error.localizedDescription
            throw error
        } catch {
            let authError = AuthError.networkError(error)
            self.errorMessage = authError.localizedDescription
            throw authError
        }
    }
}
