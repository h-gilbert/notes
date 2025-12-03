import Foundation

enum Constants {
    enum API {
        // Production URL (endpoints already include /api)
        static let baseURL = "https://notes.hamishgilbert.com"
        // Development URLs:
        // - Simulator: http://localhost:8088
        // - Physical device on local network: http://192.168.1.75:8088
        static let version = "v1"
    }

    enum App {
        static let bundleIdentifier = "com.hamish.Notes"
        static let appName = "Notes"
    }

    enum Storage {
        static let lastSyncDateKey = "lastSyncDate"
        static let authTokenKey = "authToken"
        static let deletedNoteIDsKey = "deletedNoteIDs"
    }

    enum UI {
        static let noteCardMinHeight: CGFloat = 80
        static let noteCardMaxHeight: CGFloat = 250
        static let gridSpacing: CGFloat = 12
        static let gridColumns = 2
    }

    enum Animation {
        static let defaultDuration: Double = 0.3
        static let springResponse: Double = 0.3
        static let springDamping: Double = 0.8
    }

    enum WebSocket {
        static let pingInterval: TimeInterval = 30.0
        static let maxReconnectAttempts = 5
        static let initialReconnectDelay: TimeInterval = 1.0
        static let maxReconnectDelay: TimeInterval = 30.0
    }
}
