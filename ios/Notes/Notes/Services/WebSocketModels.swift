import Foundation

// MARK: - WebSocket Message Types

enum WSMessageType: String, Codable, Sendable {
    case noteCreated = "note_created"
    case noteUpdated = "note_updated"
    case noteDeleted = "note_deleted"
    case ping = "ping"
    case pong = "pong"
}

// MARK: - WebSocket Message

nonisolated struct WSMessage: Codable, Sendable {
    let type: WSMessageType
    let payload: WSPayload?

    enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    init(type: WSMessageType, payload: WSPayload? = nil) {
        self.type = type
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(WSMessageType.self, forKey: .type)

        // Decode payload based on message type
        switch type {
        case .noteCreated, .noteUpdated:
            payload = try container.decodeIfPresent(NoteChangePayload.self, forKey: .payload)
        case .noteDeleted:
            payload = try container.decodeIfPresent(NoteDeletePayload.self, forKey: .payload)
        case .ping, .pong:
            payload = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)

        // Encode payload based on type
        if let notePayload = payload as? NoteChangePayload {
            try container.encode(notePayload, forKey: .payload)
        } else if let deletePayload = payload as? NoteDeletePayload {
            try container.encode(deletePayload, forKey: .payload)
        }
    }
}

// MARK: - Payload Protocol

protocol WSPayload: Codable, Sendable {}

// MARK: - Note Change Payload

nonisolated struct NoteChangePayload: WSPayload {
    let note: NoteDTO
}

// MARK: - Note Delete Payload

nonisolated struct NoteDeletePayload: WSPayload {
    let noteId: String
}

// MARK: - Connection Status

enum WebSocketConnectionStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
}

// MARK: - WebSocket Error

enum WebSocketError: Error, LocalizedError, Sendable {
    case invalidURL
    case notConnected
    case connectionFailed(String)
    case encodingError
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .notConnected:
            return "WebSocket not connected"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .encodingError:
            return "Failed to encode message"
        case .decodingError(let reason):
            return "Failed to decode message: \(reason)"
        }
    }
}
