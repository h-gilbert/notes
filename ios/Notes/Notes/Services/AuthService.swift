import Foundation

// MARK: - Auth Models

struct AuthRequest: Codable, Sendable {
    let username: String
    let password: String
}

struct AuthResponse: Codable, Sendable {
    let token: String
    let user: UserDTO
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

    // Token refresh settings
    private let tokenRefreshThreshold: TimeInterval = 24 * 60 * 60 // Refresh if expiring in 24 hours
    private var refreshTimer: Timer?

    private init() {
        self.baseURL = Constants.API.baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        // Check for existing token on init
        if let token = UserDefaults.standard.string(forKey: Constants.Storage.authTokenKey) {
            // Check if token is expired or needs refresh
            Task {
                await initializeWithToken(token)
            }
        }
    }

    private func initializeWithToken(_ token: String) async {
        if isTokenExpired(token) {
            // Token is expired, user needs to log in again
            print("AuthService: Token is expired, logging out")
            logout()
            return
        }

        self.isAuthenticated = true
        await configureAPIClient(token: token)

        // Check if token needs refresh
        if shouldRefreshToken(token) {
            print("AuthService: Token expiring soon, refreshing...")
            await refreshTokenIfNeeded()
        }

        // Start periodic token refresh check
        startTokenRefreshTimer()
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
        UserDefaults.standard.removeObject(forKey: Constants.Storage.authTokenKey)
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

    // MARK: - Token Refresh

    func refreshTokenIfNeeded() async {
        guard let token = UserDefaults.standard.string(forKey: Constants.Storage.authTokenKey) else {
            return
        }

        // Don't refresh if token is already expired (user needs to login again)
        if isTokenExpired(token) {
            print("AuthService: Token expired, user needs to login again")
            logout()
            return
        }

        // Only refresh if token is expiring soon
        guard shouldRefreshToken(token) else {
            return
        }

        do {
            let response: AuthResponse = try await performAuthenticatedRequest(
                endpoint: "/api/auth/refresh",
                method: "POST",
                token: token
            )

            // Update stored token
            UserDefaults.standard.set(response.token, forKey: Constants.Storage.authTokenKey)
            currentUser = response.user

            // Update API client with new token
            await configureAPIClient(token: response.token)

            // Reconnect WebSocket with new token
            await WebSocketService.shared.disconnect()
            await WebSocketService.shared.connect(token: response.token)

            print("AuthService: Token refreshed successfully")
        } catch {
            print("AuthService: Failed to refresh token: \(error)")
            // If refresh fails due to 401, logout the user
            if case AuthError.invalidCredentials = error {
                logout()
            }
        }
    }

    // MARK: - Private Methods

    private func handleAuthSuccess(response: AuthResponse) async {
        UserDefaults.standard.set(response.token, forKey: Constants.Storage.authTokenKey)
        currentUser = response.user
        isAuthenticated = true

        await configureAPIClient(token: response.token)

        // Connect WebSocket for real-time updates
        await WebSocketService.shared.connect(token: response.token)

        // Start periodic token refresh check
        startTokenRefreshTimer()
    }

    private func configureAPIClient(token: String) async {
        await APIClient.shared.configure(baseURL: baseURL, authToken: token)
    }

    private func startTokenRefreshTimer() {
        refreshTimer?.invalidate()
        // Check every hour if token needs refresh
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
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
        return timeUntilExpiry < tokenRefreshThreshold
    }

    private func getTokenExpirationDate(_ token: String) -> Date? {
        // JWT structure: header.payload.signature
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        // Decode the payload (second part)
        var payload = String(parts[1])
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

    private func performAuthenticatedRequest<T: Decodable>(
        endpoint: String,
        method: String,
        token: String
    ) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

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
            default:
                throw AuthError.serverError("Request failed with status \(httpResponse.statusCode)")
            }
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.networkError(error)
        }
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
