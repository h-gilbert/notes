import Foundation

enum Constants {
    enum API {
        // Base URL is determined by build configuration
        // In production builds, this should be set via build settings or Info.plist
        static var baseURL: String {
            #if DEBUG
            // Development: Use localhost for simulator, local IP for device
            #if targetEnvironment(simulator)
            return "http://localhost:8088"
            #else
            // For physical device testing, update this to your local network IP
            return "http://localhost:8088"
            #endif
            #else
            // Production: Use environment variable or default
            if let urlString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
               !urlString.isEmpty {
                return urlString
            }
            // Fallback - should be configured in build settings
            return "https://your-api-domain.com"
            #endif
        }
        static let version = "v1"
    }

    enum App {
        static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.notes.app"
        static let appName = "Notes"
    }

    enum Storage {
        // Note: Auth tokens are now stored in Keychain via KeychainHelper
        static let lastSyncDateKey = "lastSyncDate"
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

    enum Security {
        // Certificate pinning is configured in CertificatePinning.swift
        // Public key hashes can be set via Info.plist:
        //   - PINNED_PUBLIC_KEY_HASHES: Array of base64 SHA256 hashes
        //   - PINNED_DOMAINS: Array of domains to pin (empty = all HTTPS)
        //
        // To generate your server's public key hash:
        // openssl s_client -connect your-domain.com:443 -servername your-domain.com 2>/dev/null | \
        //   openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | \
        //   openssl dgst -sha256 -binary | base64
        //
        // Certificate pinning is automatically disabled in DEBUG builds
        // to allow local development with self-signed certificates.
    }
}
