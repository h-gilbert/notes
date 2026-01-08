@preconcurrency import Foundation

// MARK: - API Error Types

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case encodingError(Error)
    case networkError(Error)
    case unauthorized
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let message):
            return "HTTP Error \(statusCode): \(message ?? "Unknown error")"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized - please log in again"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

// MARK: - DTO Converter (MainActor)

@MainActor
enum DTOConverter {
    static func noteDTO(from note: Note) -> NoteDTO {
        NoteDTO(
            id: note.serverID ?? note.id.uuidString,
            title: note.title,
            content: note.content,
            noteType: note.noteType.rawValue,
            isPinned: note.isPinned,
            isArchived: note.isArchived,
            sortOrder: note.sortOrder,
            createdAt: ISO8601DateFormatter().string(from: note.createdAt),
            updatedAt: ISO8601DateFormatter().string(from: note.updatedAt),
            checklistItems: note.checklistItems?.map { checklistItemDTO(from: $0) }
        )
    }

    static func checklistItemDTO(from item: ChecklistItem) -> ChecklistItemDTO {
        ChecklistItemDTO(
            id: item.id.uuidString,
            text: item.text,
            isCompleted: item.isCompleted,
            sortOrder: item.sortOrder,
            createdAt: ISO8601DateFormatter().string(from: item.createdAt),
            updatedAt: ISO8601DateFormatter().string(from: item.updatedAt)
        )
    }
}

// MARK: - API Client

actor APIClient {
    static let shared = APIClient()

    private var baseURL: URL?
    private var authToken: String?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60

        // Use certificate pinning delegate for secure connections
        // In debug mode, pinning is disabled to allow local development
        self.session = URLSession(
            configuration: configuration,
            delegate: CertificatePinningDelegate.shared,
            delegateQueue: nil
        )

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Configuration

    func configure(baseURL: String, authToken: String?) {
        self.baseURL = URL(string: baseURL)
        self.authToken = authToken
    }

    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    // MARK: - Notes API

    func fetchNotes(since lastSync: Date?) async throws -> SyncResponse {
        var components = URLComponents()
        components.path = "/api/notes"

        if let lastSync = lastSync {
            components.queryItems = [
                URLQueryItem(name: "since", value: ISO8601DateFormatter().string(from: lastSync))
            ]
        }

        return try await request(
            method: "GET",
            path: components.string ?? "/api/notes",
            body: nil as String?
        )
    }

    func createNote(_ note: NoteDTO) async throws -> NoteDTO {
        return try await request(
            method: "POST",
            path: "/api/notes",
            body: note
        )
    }

    func updateNote(_ note: NoteDTO) async throws -> NoteDTO {
        return try await request(
            method: "PUT",
            path: "/api/notes/\(note.id)",
            body: note
        )
    }

    func deleteNote(id: String) async throws {
        let _: EmptyResponse = try await request(
            method: "DELETE",
            path: "/api/notes/\(id)",
            body: nil as String?
        )
    }

    func syncNotes(changes: [NoteDTO], deletedIDs: [String], lastSync: Date?) async throws -> SyncResponse {
        struct SyncRequest: Codable, Sendable {
            let changes: [NoteDTO]
            let deletedIDs: [String]
            let lastSync: String?
        }

        let requestBody = SyncRequest(
            changes: changes,
            deletedIDs: deletedIDs,
            lastSync: lastSync.map { ISO8601DateFormatter().string(from: $0) }
        )

        return try await request(
            method: "POST",
            path: "/api/notes/sync",
            body: requestBody
        )
    }

    // MARK: - Generic Request

    private func request<T: Decodable, B: Encodable>(
        method: String,
        path: String,
        body: B?
    ) async throws -> T {
        guard let baseURL = baseURL else {
            throw APIError.invalidURL
        }

        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            do {
                request.httpBody = try Self.encode(body)
            } catch {
                throw APIError.encodingError(error)
            }
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200...299:
                do {
                    return try Self.decode(T.self, from: data)
                } catch {
                    throw APIError.decodingError(error)
                }
            case 401:
                throw APIError.unauthorized
            case 400...499:
                let errorMessage = String(data: data, encoding: .utf8)
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
            case 500...599:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Internal server error"
                throw APIError.serverError(errorMessage)
            default:
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: nil)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Nonisolated Encoding/Decoding

    nonisolated private static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    nonisolated private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
