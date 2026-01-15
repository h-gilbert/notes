import Foundation
import CommonCrypto
import Security

// MARK: - Certificate Pinning Error

enum CertificatePinningError: Error, LocalizedError {
    case noCertificateFound
    case invalidCertificate
    case publicKeyMismatch
    case pinningFailed(String)

    var errorDescription: String? {
        switch self {
        case .noCertificateFound:
            return "No server certificate found"
        case .invalidCertificate:
            return "Invalid server certificate"
        case .publicKeyMismatch:
            return "Server certificate public key does not match pinned key"
        case .pinningFailed(let reason):
            return "Certificate pinning failed: \(reason)"
        }
    }
}

// MARK: - Certificate Pinning Configuration

enum CertificatePinningConfig {
    /// SHA256 hashes of the public keys to pin against
    /// Generate with: openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
    ///
    /// To get your server's public key hash:
    /// 1. Run: openssl s_client -connect your-domain.com:443 -servername your-domain.com 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
    /// 2. Add the output to this array
    ///
    /// Include backup pins for certificate rotation:
    /// - Current certificate's public key
    /// - Backup/next certificate's public key (if known)
    static var pinnedPublicKeyHashes: [String] {
        #if DEBUG
        // In debug mode, return empty array to disable pinning for local development
        return []
        #else
        // Production: Add your server's public key hash(es) here
        // You can pin multiple keys for backup/rotation purposes
        if let hashes = Bundle.main.object(forInfoDictionaryKey: "PINNED_PUBLIC_KEY_HASHES") as? [String],
           !hashes.isEmpty {
            return hashes
        }

        // ⚠️ SECURITY WARNING: Certificate pinning is REQUIRED for production!
        // Without pinning, the app is vulnerable to man-in-the-middle attacks.
        //
        // To generate your certificate pin hash, run:
        // openssl s_client -connect YOUR_DOMAIN:443 -servername YOUR_DOMAIN 2>/dev/null | \
        //   openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | \
        //   openssl dgst -sha256 -binary | base64
        //
        // Then either:
        // 1. Add PINNED_PUBLIC_KEY_HASHES array to Info.plist, OR
        // 2. Add the hash(es) to the array below
        //
        // Include at least 2 pins: current cert + backup cert for rotation
        return [
            // Primary: notes.hamishgilbert.com certificate (generated 2026-01-09)
            "gXP2zdjWMTp7cLBOgHatnMUsbhM3tUSGKuqIePzNvQk=",
            // Backup: Add your backup/next certificate's public key hash here before rotating certs
            // Generate with: openssl s_client -connect YOUR_DOMAIN:443 -servername YOUR_DOMAIN 2>/dev/null | \
            //   openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
        ]
        #endif
    }

    /// Whether certificate pinning is enabled
    static var isEnabled: Bool {
        #if DEBUG
        return false // Disable in debug for local development
        #else
        return !pinnedPublicKeyHashes.isEmpty
        #endif
    }

    /// Domains to apply pinning to (empty means all HTTPS domains)
    static var pinnedDomains: [String] {
        if let domains = Bundle.main.object(forInfoDictionaryKey: "PINNED_DOMAINS") as? [String] {
            return domains
        }
        return [] // Empty means pin all HTTPS connections
    }
}

// MARK: - Certificate Pinning Delegate

final class CertificatePinningDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {

    static let shared = CertificatePinningDelegate()

    private override init() {
        super.init()
    }

    // MARK: - URLSessionDelegate

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    // MARK: - URLSessionTaskDelegate

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    // MARK: - Challenge Handling

    private func handleChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only handle server trust challenges
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Check if pinning is enabled
        guard CertificatePinningConfig.isEnabled else {
            // Pinning disabled - use default certificate validation
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Check if this domain should be pinned
        let pinnedDomains = CertificatePinningConfig.pinnedDomains
        if !pinnedDomains.isEmpty && !pinnedDomains.contains(where: { host.hasSuffix($0) }) {
            // Domain not in pinned list - use default validation
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Validate the certificate chain first
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)

        guard isValid else {
            print("[CertPinning] Certificate chain validation failed for \(host): \(error?.localizedDescription ?? "unknown")")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Extract and validate public key
        do {
            let isKeyValid = try validatePublicKey(serverTrust: serverTrust, host: host)
            if isKeyValid {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
            } else {
                print("[CertPinning] Public key validation failed for \(host)")
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } catch {
            print("[CertPinning] Error validating public key for \(host): \(error)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: - Public Key Validation

    private func validatePublicKey(serverTrust: SecTrust, host: String) throws -> Bool {
        let pinnedHashes = CertificatePinningConfig.pinnedPublicKeyHashes
        guard !pinnedHashes.isEmpty else {
            // No pins configured - allow connection (shouldn't happen if isEnabled is true)
            return true
        }

        // Get the certificate chain
        let certificates: [SecCertificate]
        if #available(iOS 15.0, *) {
            guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
                  !chain.isEmpty else {
                throw CertificatePinningError.noCertificateFound
            }
            certificates = chain
        } else {
            // Fallback for older iOS versions
            let count = SecTrustGetCertificateCount(serverTrust)
            guard count > 0 else {
                throw CertificatePinningError.noCertificateFound
            }
            var certs: [SecCertificate] = []
            for index in 0..<count {
                if let cert = SecTrustGetCertificateAtIndex(serverTrust, index) {
                    certs.append(cert)
                }
            }
            certificates = certs
        }

        // Check each certificate in the chain (usually just need leaf, but checking chain adds flexibility)
        for (index, certificate) in certificates.enumerated() {
            // Extract public key from certificate
            guard let publicKey = SecCertificateCopyKey(certificate) else {
                continue
            }

            // Get public key data
            guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
                continue
            }

            // Calculate SHA256 hash of public key
            let hash = sha256Hash(of: publicKeyData)
            let hashBase64 = hash.base64EncodedString()

            #if DEBUG
            print("[CertPinning] Certificate \(index) public key hash: \(hashBase64)")
            #endif

            // Check if this hash matches any pinned hash
            if pinnedHashes.contains(hashBase64) {
                #if DEBUG
                print("[CertPinning] Public key match found for \(host)")
                #endif
                return true
            }
        }

        // No matching pin found
        print("[CertPinning] No matching public key found for \(host)")
        print("[CertPinning] Expected one of: \(pinnedHashes)")
        throw CertificatePinningError.publicKeyMismatch
    }

    // MARK: - Hashing

    private func sha256Hash(of data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}

// MARK: - URLSession Extension for Pinning

extension URLSession {
    /// Creates a URLSession configured with certificate pinning
    static func pinnedSession(configuration: URLSessionConfiguration = .default) -> URLSession {
        return URLSession(
            configuration: configuration,
            delegate: CertificatePinningDelegate.shared,
            delegateQueue: nil
        )
    }
}
