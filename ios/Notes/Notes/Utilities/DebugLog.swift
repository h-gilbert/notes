import Foundation

/// Debug logging utility that only prints in DEBUG builds
/// Usage: debugLog("Message") or debugLog("Message", category: "WebSocket")
func debugLog(_ message: String, category: String? = nil, file: String = #file, line: Int = #line) {
    #if DEBUG
    let filename = (file as NSString).lastPathComponent
    if let category = category {
        print("[\(category)] \(filename):\(line) - \(message)")
    } else {
        print("\(filename):\(line) - \(message)")
    }
    #endif
}

/// Shorthand for WebSocket-related debug logs
func wsLog(_ message: String) {
    #if DEBUG
    print("🔌 WS: \(message)")
    #endif
}

/// Shorthand for Auth-related debug logs
func authLog(_ message: String) {
    #if DEBUG
    print("🔐 Auth: \(message)")
    #endif
}

/// Shorthand for Sync-related debug logs
func syncLog(_ message: String) {
    #if DEBUG
    print("🔄 Sync: \(message)")
    #endif
}
