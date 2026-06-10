import SwiftUI
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins
import PhotosUI
import Photos

struct SendView: View {
    @State private var ticket: String?
    @State private var pickedLabel: String?
    @State private var picking = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var working = false
    @State private var errorMessage: String?
    @State private var receivedCount: UInt64 = 0

    /// 1Hz tick to refresh the receiver count while a ticket is on screen.
    private let receivedTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let ticket {
                        ticketBlock(ticket: ticket)
                    } else {
                        Button {
                            picking = true
                        } label: {
                            Label("Pick files", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(working)

                        PhotosPicker(
                            selection: $photoItems,
                            maxSelectionCount: 0,
                            matching: .any(of: [.images, .videos]),
                            photoLibrary: .shared()
                        ) {
                            Label("Pick photos", systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(working)

                        if working {
                            ProgressView("Hashing \(pickedLabel ?? "")…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Send")
            .fileImporter(
                isPresented: $picking,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handlePick(result)
            }
            .onChange(of: photoItems) { newItems in
                guard !newItems.isEmpty else { return }
                Task { await sharePickedPhotos(newItems) }
            }
        }
    }

    @ViewBuilder
    private func ticketBlock(ticket: String) -> some View {
        VStack(spacing: 16) {
            if let cg = qrCode(from: ticket) {
                Image(decorative: cg, scale: 1, orientation: .up)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240)
                    .padding(8)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let pickedLabel {
                Text(pickedLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Received by \(receivedCount) \(receivedCount >= 2 ? "friends" : "friend")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ShareLink(item: ticket) {
                Label("Share ticket", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button("Pick another file") {
                reset()
            }
            .buttonStyle(.bordered)

            Text("Keep this screen open until your friend has finished receiving.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .onReceive(receivedTimer) { _ in
            Task { receivedCount = await AtmanBridge.shared.transferCount(ticket: ticket) }
        }
    }

    /// Export each picked asset directly from PhotoKit so we ship the
    /// original encoding (HEIC stays HEIC, not transcoded to JPEG) and the
    /// original filename. For Live Photos we currently only ship the still;
    /// every picked asset becomes one entry in the resulting collection
    /// ticket.
    private func sharePickedPhotos(_ items: [PhotosPickerItem]) async {
        await MainActor.run { errorMessage = nil }

        let identifiers = items.compactMap { $0.itemIdentifier }
        guard !identifiers.isEmpty else {
            await MainActor.run {
                errorMessage = "Couldn't identify the picked photos."
                photoItems = []
            }
            return
        }

        let authorized = await ensurePhotosReadAuthorization()
        guard authorized else {
            await MainActor.run {
                errorMessage = "Photos access was denied."
                photoItems = []
            }
            return
        }

        do {
            var urls: [URL] = []
            for id in identifiers {
                urls.append(try await exportOriginal(identifier: id))
            }
            await MainActor.run {
                photoItems = []
                shareFiles(at: urls)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                photoItems = []
            }
        }
    }

    /// Ask for Photos read access. `.limited` (iOS's "Selected Photos" mode)
    /// is enough — iOS automatically grants access to whatever the user just
    /// picked.
    private func ensurePhotosReadAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    cont.resume(returning: newStatus == .authorized || newStatus == .limited)
                }
            }
        default:
            return false
        }
    }

    /// Stream the original asset bytes into a temp file using PhotoKit's
    /// `PHAssetResourceManager` (which does no transcoding).
    private func exportOriginal(identifier: String) async throws -> URL {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else {
            throw photoKitError("Photo not found in library.")
        }

        let resources = PHAssetResource.assetResources(for: asset)
        // For videos prefer the original video resource; for everything else
        // (still photos, Live Photos) prefer the original still.
        let preferred: [PHAssetResourceType] = asset.mediaType == .video
            ? [.video, .fullSizeVideo]
            : [.photo, .fullSizePhoto]
        guard let resource = resources.first(where: { preferred.contains($0.type) })
            ?? resources.first
        else {
            throw photoKitError("No asset resource found.")
        }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("beam-out", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let dest = tmpDir.appendingPathComponent(
            "\(UUID().uuidString.prefix(6))-\(resource.originalFilename)"
        )
        // PhotoKit's writeData(for:toFile:) wants a fresh destination.
        try? FileManager.default.removeItem(at: dest)

        let options = PHAssetResourceRequestOptions()
        // Fetch iCloud-only assets if the picked photo isn't on-device.
        options.isNetworkAccessAllowed = true

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: dest,
                options: options
            ) { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? -1
        print("beam SendView: exported \(resource.type.rawValue) for \(identifier) → \(dest.path) (\(size) bytes)")
        return dest
    }

    private func photoKitError(_ message: String) -> Error {
        NSError(domain: "SendView", code: 0, userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        errorMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard !urls.isEmpty else { return }
            shareFiles(at: urls)
        }
    }

    private func shareFiles(at urls: [URL]) {
        pickedLabel = urls.count == 1
            ? urls[0].lastPathComponent
            : "\(urls.count) files"
        working = true
        for url in urls {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
            print("beam SendView: shareFiles → \(url.path) (\(size) bytes)")
        }
        Task.detached {
            // Many picked URLs are security-scoped (iCloud Drive etc.).
            let granted = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer {
                for (url, ok) in granted where ok {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let t = try await AtmanBridge.shared.sendFiles(at: urls)
                await MainActor.run {
                    self.ticket = t
                    self.working = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.working = false
                }
            }
        }
    }

    private func reset() {
        ticket = nil
        pickedLabel = nil
        errorMessage = nil
        receivedCount = 0
    }

    private func qrCode(from string: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Scale up so the QR isn't tiny when SwiftUI rasterizes it.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ctx = CIContext()
        return ctx.createCGImage(scaled, from: scaled.extent)
    }
}
