import Foundation
import Security

/// Thin Swift wrapper over atman's C ABI. All entry points are synchronous
/// and may block — call from a background queue or a `Task.detached`.
enum AtmanBridge {

    enum Error: Swift.Error, LocalizedError {
        case alreadyInitialized
        case initFailed(code: UInt16)
        case randomFailed(status: OSStatus)
        case nullReply

        var errorDescription: String? {
            switch self {
            case .alreadyInitialized: return "Atman is already initialized."
            case .initFailed(let code): return "Atman init failed (code \(code))."
            case .randomFailed(let status): return "Failed to generate random bytes (OSStatus \(status))."
            case .nullReply: return "Atman returned NULL."
            }
        }
    }

    private static var didInitialize = false

    /// Spin up the atman daemon. Idempotent — second call is a no-op.
    static func initializeIfNeeded() throws {
        guard !didInitialize else { return }

        let identityHex = try randomHex32()
        let networkKeyHex = try randomHex32()

        // Beam links atman built with `--features blobs` only — no `sync`.
        // The C ABI's `syncman_dir` arg still exists because cbindgen
        // doesn't support `--features`, but the arg is unread.
        // So we pass an empty C string.
        let code = identityHex.withCString { id in
            networkKeyHex.withCString { nk in
                "".withCString { dir in
                    run_atman(id, nk, nil, dir, 0)
                }
            }
        }
        guard code == 0 else { throw Error.initFailed(code: code) }
        didInitialize = true
    }

    /// Import one or more files into atman's blob store. A single URL
    /// produces a raw ticket; two or more bundle into a HashSeq collection
    /// ticket. The C ABI takes newline-separated paths in one C string.
    static func sendFiles(at urls: [URL]) throws -> String {
        precondition(!urls.isEmpty, "sendFiles requires at least one URL")
        let joined = urls.map { $0.path }.joined(separator: "\n")
        let ptr: UnsafeMutablePointer<CChar>? = joined.withCString { p in
            send_atman_blobs_add_files_command(p)
        }
        guard let ptr else { throw Error.nullReply }
        defer { free_string(ptr) }
        return String(cString: ptr)
    }

    /// How many receivers have fully pulled `ticket`. Returns 0 if the
    /// ticket isn't ours or no one has received yet. Re-sharing
    /// identical content aggregates into one counter.
    static func transferCount(ticket: String) -> UInt64 {
        ticket.withCString { send_atman_blobs_files_transfer_count_command($0) }
    }

    /// Pull every blob described by `ticket` into `saveDir`. Returns one
    /// URL per saved file (length 1 for a raw ticket, N for a collection).
    /// atman returns newline-separated paths over the C ABI.
    static func downloadFiles(ticket: String, into saveDir: URL) throws -> [URL] {
        let ptr: UnsafeMutablePointer<CChar>? = ticket.withCString { t in
            saveDir.path.withCString { d in
                send_atman_blobs_download_files_command(t, d)
            }
        }
        guard let ptr else { throw Error.nullReply }
        defer { free_string(ptr) }
        let joined = String(cString: ptr)
        return joined
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { URL(fileURLWithPath: String($0)) }
    }

    // MARK: - Helpers

    private static func randomHex32() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw Error.randomFailed(status: status) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
