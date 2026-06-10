import Foundation
import Security

/// App-wide handle to the UniFFI-generated `AtmanClient`.
actor AtmanBridge {
    static let shared = AtmanBridge()

    enum Error: Swift.Error, LocalizedError {
        case notInitialized
        case randomFailed(status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .notInitialized: return "Atman has not been initialized yet."
            case .randomFailed(let status): return "Failed to generate random bytes (OSStatus \(status))."
            }
        }
    }

    private var client: AtmanClient?

    /// Idempotent — second call is a no-op.
    func initializeIfNeeded() async throws {
        guard client == nil else { return }
        let identityHex = try Self.randomHex32()
        let networkKeyHex = try Self.randomHex32()
        client = try await AtmanClient(
            identityHex: identityHex,
            networkKeyHex: networkKeyHex,
            customRelayUrl: nil,
            // `sync` feature is off in beam-ios; these are ignored.
            syncmanDir: "",
            syncIntervalSecs: 0
        )
    }

    func sendFiles(at urls: [URL]) async throws -> String {
        guard let client else { throw Error.notInitialized }
        return try await client.sendFiles(paths: urls.map { $0.path })
    }

    /// Returns 0 on any error so the 1Hz poll in `SendView` doesn't flap.
    func transferCount(ticket: String) async -> UInt64 {
        guard let client else { return 0 }
        return (try? await client.transferCount(ticket: ticket)) ?? 0
    }

    func downloadFiles(ticket: String, into saveDir: URL) async throws -> [URL] {
        guard let client else { throw Error.notInitialized }
        let paths = try await client.downloadFiles(ticket: ticket, saveDir: saveDir.path)
        return paths.map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Helpers

    private static func randomHex32() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw Error.randomFailed(status: status) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
