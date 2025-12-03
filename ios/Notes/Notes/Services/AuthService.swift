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

    private init() {
        self.baseURL = Constants.API.baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        // Check for existing token on init
        if let token = UserDefaults.standard.string(forKey: Constants.Storage.authTokenKey) {
            self.isAuthenticated = true
            Task {
                await configureAPIClient(token: token)
            }
        }
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

    // MARK: - Private Methods

    private func handleAuthSuccess(response: AuthResponse) async {
        UserDefaults.standard.set(response.token, forKey: Constants.Storage.authTokenKey)
        currentUser = response.user
        isAuthenticated = true

        await configureAPIClient(token: response.token)

        // Connect WebSocket for real-time updates
        await WebSocketService.shared.connect(token: response.token)
    }

    private func configureAPIClient(token: String) async {
        await APIClient.shared.configure(baseURL: baseURL, authToken: token)
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
