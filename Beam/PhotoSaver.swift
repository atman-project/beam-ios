import Foundation
import Photos

/// Routes a downloaded file to the right user-visible location:
/// - images & videos → system Photos library (via PHPhotoLibrary)
/// - everything else → app's Documents directory (Files-app exposed as
///   "On My iPhone → Beam")
enum PhotoSaver {
    enum SaveResult {
        case photos
        case documents(URL)
        case failure(Error)
    }

    /// Per-file outcome aggregated across a multi-file transfer.
    struct Summary {
        var photosSaved: Int = 0
        var documentsSaved: Int = 0
        /// Errors collected so the UI can surface "saved 2, 1 failed."
        var failures: [Error] = []
    }

    static func save(stagedFiles: [URL]) async -> Summary {
        var summary = Summary()
        for url in stagedFiles {
            switch await save(stagedFile: url) {
            case .photos: summary.photosSaved += 1
            case .documents: summary.documentsSaved += 1
            case .failure(let e): summary.failures.append(e)
            }
        }
        return summary
    }

    static func save(stagedFile: URL) async -> SaveResult {
        let ext = stagedFile.pathExtension.lowercased()
        if isImageExt(ext) {
            return await saveAsset(stagedFile, resourceType: .photo)
        } else if isVideoExt(ext) {
            return await saveAsset(stagedFile, resourceType: .video)
        }
        return saveToDocuments(stagedFile)
    }

    // MARK: - Photos

    private static func saveAsset(_ url: URL, resourceType: PHAssetResourceType) async -> SaveResult {
        let authorized = await ensureAddOnlyAuthorization()
        guard authorized else {
            return .failure(NSError(domain: "PhotoSaver", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Photos access was denied."
            ]))
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: resourceType, fileURL: url, options: nil)
            }
            // Best-effort cleanup of the staging file.
            try? FileManager.default.removeItem(at: url)
            return .photos
        } catch {
            return .failure(error)
        }
    }

    private static func ensureAddOnlyAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                    cont.resume(returning: newStatus == .authorized || newStatus == .limited)
                }
            }
        default:
            return false
        }
    }

    // MARK: - Documents

    private static func saveToDocuments(_ src: URL) -> SaveResult {
        do {
            let docs = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dest = uniquePath(in: docs, name: src.lastPathComponent)
            try FileManager.default.moveItem(at: src, to: dest)
            return .documents(dest)
        } catch {
            return .failure(error)
        }
    }

    /// Where `saveToDocuments` puts non-Photos files. Exposed so the UI can
    /// open Files navigated to this exact directory.
    static var documentsDirectory: URL? {
        try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }

    private static func uniquePath(in dir: URL, name: String) -> URL {
        let candidate = dir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }

        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for i in 1..<10_000 {
            let suffix = ext.isEmpty ? "\(stem) (\(i))" : "\(stem) (\(i)).\(ext)"
            let next = dir.appendingPathComponent(suffix)
            if !FileManager.default.fileExists(atPath: next.path) { return next }
        }
        return dir.appendingPathComponent("\(stem)-\(ProcessInfo.processInfo.processIdentifier).\(ext)")
    }

    // MARK: - Extension classifiers

    private static func isImageExt(_ ext: String) -> Bool {
        ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff"].contains(ext)
    }

    private static func isVideoExt(_ ext: String) -> Bool {
        ["mp4", "mov", "m4v", "hevc", "qt"].contains(ext)
    }
}
