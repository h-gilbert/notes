import Foundation
import SwiftData
import UIKit

// MARK: - WebSocket Event

enum WebSocketEvent: Sendable {
    case message(WSMessage)
    case connected
    case disconnected
    case error(String)
}

// MARK: - WebSocket Actor (Network Layer)

actor WebSocketActor {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    private var eventContinuation: AsyncStream<WebSocketEvent>.Continuation?

    // Ping interval constant (avoid main actor isolation)
    private let pingInterval: TimeInterval = 30.0

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Event Stream

    func eventStream() -> AsyncStream<WebSocketEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.handleStreamTermination() }
            }
        }
    }

    private func handleStreamTermination() {
        eventContinuation = nil
    }

    private func emit(_ event: WebSocketEvent) {
        eventContinuation?.yield(event)
    }

    // MARK: - Connection

    func connect(baseURL: String, token: String) throws {
        // Close existing connection if any
        disconnectInternal()

        // Convert HTTP URL to WebSocket URL
        let wsURL = baseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")

        guard var urlComponents = URLComponents(string: wsURL) else {
            throw WebSocketError.invalidURL
        }

        urlComponents.path = "/api/ws"
        urlComponents.queryItems = [URLQueryItem(name: "token", value: token)]

        guard let url = urlComponents.url else {
            throw WebSocketError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        print("🔌 WebSocket: Connecting to \(url)")

        // Start receiving messages
        startReceiving()

        // Start ping interval
        startPingInterval()

        emit(.connected)
    }

    func disconnect() {
        disconnectInternal()
        emit(.disconnected)
    }

    private func disconnectInternal() {
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil

        webSocketTask?.cancel(with: .normalClosure, reason: "Client disconnect".data(using: .utf8))
        webSocketTask = nil
    }

    // MARK: - Message Sending

    func send(_ message: WSMessage) async throws {
        guard let task = webSocketTask else {
            throw WebSocketError.notConnected
        }

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        try await task.send(.data(data))
    }

    private func sendPing() async throws {
        let message = WSMessage(type: .ping)
        try await send(message)
    }

    // MARK: - Message Receiving

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        print("🔄 WebSocket: Receive loop started")
        while !Task.isCancelled {
            do {
                guard let task = webSocketTask else {
                    print("⚠️ WebSocket: No task in receive loop")
                    break
                }

                let message = try await task.receive()

                switch message {
                case .data(let data):
                    handleReceivedData(data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        handleReceivedData(data)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    emit(.error(error.localizedDescription))
                    emit(.disconnected)
                }
                break
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        // Debug: print raw message
        if let rawString = String(data: data, encoding: .utf8) {
            print("📥 WebSocket RAW: \(rawString)")
        }

        do {
            let decoder = JSONDecoder()
            let message = try decoder.decode(WSMessage.self, from: data)
            emit(.message(message))
        } catch {
            print("❌ WebSocket: Failed to decode message: \(error)")
        }
    }

    // MARK: - Ping/Pong Keep-Alive

    private func startPingInterval() {
        pingTask = Task { [weak self] in
            await self?.pingLoop()
        }
    }

    private func pingLoop() async {
        while !Task.isCancelled {
            let interval = UInt64(pingInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: interval)
            guard !Task.isCancelled else { break }

            do {
                try await sendPing()
            } catch {
                print("WebSocket: Ping failed: \(error)")
                break
            }
        }
    }

    var isConnected: Bool {
        webSocketTask?.state == .running
    }
}

// MARK: - WebSocket Service (Observable, MainActor)

@Observable
@MainActor
final class WebSocketService {
    static let shared = WebSocketService()

    // MARK: - State

    private(set) var connectionStatus: WebSocketConnectionStatus = .disconnected
    private(set) var lastError: Error?

    // MARK: - Private Properties

    private let webSocketActor = WebSocketActor()
    private var modelContext: ModelContext?
    private var currentToken: String?

    // Event handling
    private var eventTask: Task<Void, Never>?

    // Reconnection
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private let initialReconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0

    // ISO8601 date formatter
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {
        setupNotifications()
    }

    // MARK: - Configuration

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Connection Management

    func connect(token: String) async {
        guard connectionStatus == .disconnected else { return }

        currentToken = token
        connectionStatus = .connecting
        reconnectAttempts = 0

        // Start listening for events
        startEventStream()

        do {
            try await webSocketActor.connect(
                baseURL: Constants.API.baseURL,
                token: token
            )
            connectionStatus = .connected
            lastError = nil

            // Notify SyncService that WebSocket is connected
            SyncService.shared.setWebSocketConnected(true)
        } catch {
            lastError = error
            connectionStatus = .disconnected
            scheduleReconnect()
        }
    }

    func disconnect() async {
        cancelReconnect()
        eventTask?.cancel()
        eventTask = nil
        currentToken = nil
        await webSocketActor.disconnect()
        connectionStatus = .disconnected

        // Notify SyncService that WebSocket is disconnected
        SyncService.shared.setWebSocketConnected(false)
    }

    // MARK: - Event Stream Handling

    private func startEventStream() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self = self else { return }

            let stream = await self.webSocketActor.eventStream()

            for await event in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.handleEvent(event)
                }
            }
        }
    }

    private func handleEvent(_ event: WebSocketEvent) {
        switch event {
        case .message(let message):
            print("📨 WebSocket: Received message type: \(message.type.rawValue)")
            handleMessage(message)
        case .connected:
            print("✅ WebSocket: Connected successfully!")
            connectionStatus = .connected
            SyncService.shared.setWebSocketConnected(true)
        case .disconnected:
            print("❌ WebSocket: Disconnected")
            handleDisconnect()
        case .error(let errorMessage):
            lastError = WebSocketError.connectionFailed(errorMessage)
            print("⚠️ WebSocket error: \(errorMessage)")
        }
    }

    // MARK: - Reconnection Logic

    private func scheduleReconnect() {
        guard let token = currentToken,
              reconnectAttempts < maxReconnectAttempts else {
            connectionStatus = .disconnected
            SyncService.shared.setWebSocketConnected(false)
            return
        }

        reconnectAttempts += 1
        connectionStatus = .reconnecting(attempt: reconnectAttempts)

        let delay = min(
            initialReconnectDelay * pow(2.0, Double(reconnectAttempts - 1)),
            maxReconnectDelay
        )

        reconnectTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }

                connectionStatus = .connecting
                startEventStream()

                try await webSocketActor.connect(
                    baseURL: Constants.API.baseURL,
                    token: token
                )
                connectionStatus = .connected
                reconnectAttempts = 0
                lastError = nil

                SyncService.shared.setWebSocketConnected(true)
            } catch {
                if !Task.isCancelled {
                    lastError = error
                    scheduleReconnect()
                }
            }
        }
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: WSMessage) {
        switch message.type {
        case .noteCreated, .noteUpdated:
            if let payload = message.payload as? NoteChangePayload {
                print("📝 WebSocket: \(message.type.rawValue) - '\(payload.note.title)'")
                upsertNote(from: payload.note)
            }
        case .noteDeleted:
            if let payload = message.payload as? NoteDeletePayload {
                print("🗑️ WebSocket: Note deleted - \(payload.noteId)")
                deleteNote(serverID: payload.noteId)
            }
        case .pong:
            // Keep-alive acknowledged, nothing to do
            break
        case .ping:
            // Server pinged us, send pong
            Task {
                try? await webSocketActor.send(WSMessage(type: .pong))
            }
        }
    }

    private func handleDisconnect() {
        connectionStatus = .disconnected
        SyncService.shared.setWebSocketConnected(false)
        scheduleReconnect()
    }

    // MARK: - SwiftData Updates

    private func upsertNote(from dto: NoteDTO) {
        guard let context = modelContext else {
            print("WebSocket: ModelContext not configured")
            return
        }

        do {
            // Find existing note by serverID or local UUID
            let descriptor = FetchDescriptor<Note>()
            let allNotes = try context.fetch(descriptor)

            // Try to find existing note by serverID first
            var existingNote = allNotes.first { $0.serverID == dto.id }

            // If not found by serverID, check if this matches a pending note by local UUID
            // (the server may use local UUID as the ID for newly created notes)
            if existingNote == nil {
                existingNote = allNotes.first { $0.id.uuidString == dto.id }
            }

            let note: Note
            if let existing = existingNote {
                // Skip if local note has pending changes (avoid overwriting local edits)
                if existing.syncStatus == .pending {
                    print("WebSocket: Skipping update for note with pending local changes")
                    return
                }
                note = existing
            } else {
                // Before creating a new note, check if this is an echo of a local note creation
                // This happens when we create a note locally, sync it, and then receive
                // a WebSocket notification about the same note (but with a server-assigned ID)

                // Check ALL notes without serverID (could be pending OR recently synced where
                // the sync response hasn't been fully processed yet)
                let notesWithoutServerID = allNotes.filter { $0.serverID == nil }

                for localNote in notesWithoutServerID {
                    if localNote.title == dto.title && localNote.content == dto.content {
                        print("WebSocket: Found matching local note without serverID, updating serverID")
                        localNote.serverID = dto.id
                        localNote.syncStatus = .synced
                        try context.save()
                        return
                    }
                }

                // Also check recently created/updated notes that might have a serverID set
                // but with matching content - this catches race conditions where sync completed
                // but used a different ID than what WebSocket is sending
                let recentThreshold = Date().addingTimeInterval(-30) // Within last 30 seconds
                let recentNotes = allNotes.filter { $0.createdAt > recentThreshold || $0.updatedAt > recentThreshold }

                for recentNote in recentNotes {
                    if recentNote.title == dto.title &&
                       recentNote.content == dto.content &&
                       recentNote.serverID != dto.id {
                        print("WebSocket: Found recent note with matching content, updating serverID from '\(recentNote.serverID ?? "nil")' to '\(dto.id)'")
                        recentNote.serverID = dto.id
                        recentNote.syncStatus = .synced
                        try context.save()
                        return
                    }
                }

                // This is a genuinely new note from another device
                print("WebSocket: Creating new note from server - '\(dto.title)'")
                note = Note()
                context.insert(note)
            }

            // Update note properties
            note.serverID = dto.id
            note.title = dto.title
            note.content = dto.content
            note.noteType = NoteType(rawValue: dto.noteType) ?? .note
            note.isPinned = dto.isPinned
            note.isArchived = dto.isArchived
            note.sortOrder = dto.sortOrder
            note.createdAt = dateFormatter.date(from: dto.createdAt) ?? Date()
            note.updatedAt = dateFormatter.date(from: dto.updatedAt) ?? Date()
            note.syncStatus = .synced

            // Update checklist items
            if let itemDTOs = dto.checklistItems {
                // Remove existing items
                if let existingItems = note.checklistItems {
                    for item in existingItems {
                        context.delete(item)
                    }
                }

                // Add new items
                note.checklistItems = itemDTOs.map { itemDTO in
                    let item = ChecklistItem(
                        id: UUID(uuidString: itemDTO.id) ?? UUID(),
                        text: itemDTO.text,
                        isCompleted: itemDTO.isCompleted,
                        sortOrder: itemDTO.sortOrder,
                        createdAt: dateFormatter.date(from: itemDTO.createdAt) ?? Date(),
                        updatedAt: dateFormatter.date(from: itemDTO.updatedAt) ?? Date(),
                        note: note
                    )
                    context.insert(item)
                    return item
                }
            }

            try context.save()
            print("✨ WebSocket: Note saved to local database")
        } catch {
            print("❌ WebSocket: Failed to upsert note: \(error)")
        }
    }

    private func deleteNote(serverID: String) {
        guard let context = modelContext else {
            print("WebSocket: ModelContext not configured")
            return
        }

        do {
            let descriptor = FetchDescriptor<Note>()
            let allNotes = try context.fetch(descriptor)

            if let noteToDelete = allNotes.first(where: { $0.serverID == serverID }) {
                context.delete(noteToDelete)
                try context.save()
            }
        } catch {
            print("WebSocket: Failed to delete note: \(error)")
        }
    }

    // MARK: - App Lifecycle

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAppBackgrounding()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAppForegrounding()
            }
        }
    }

    private func handleAppBackgrounding() async {
        // Disconnect cleanly when app goes to background
        await disconnect()
    }

    private func handleAppForegrounding() async {
        // Reconnect when app comes to foreground
        if let token = currentToken {
            await connect(token: token)
        } else if let token = UserDefaults.standard.string(forKey: Constants.Storage.authTokenKey) {
            await connect(token: token)
        }
    }
}
