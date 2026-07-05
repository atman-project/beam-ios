import SwiftUI
import UniformTypeIdentifiers

struct ReceiveView: View {
    @State private var manualTicket = ""
    @State private var scanning = false
    @State private var working = false
    @State private var bytesReceived: UInt64 = 0
    @State private var transferStart: Date?
    @State private var transferTask: Task<Void, Never>?
    @State private var result: SaveOutcome?
    @State private var errorMessage: String?
    @FocusState private var ticketFieldFocused: Bool

    /// Native byte formatter for the "Receiving 1.23 MB" text.
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    /// What we ended up writing across a (possibly multi-file) transfer.
    /// Drives the post-receive alert: photo count steers the Photos button,
    /// file count steers the Files button — both appear when both are > 0.
    private struct SaveOutcome {
        let photos: Int
        let files: Int
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Button {
                        scanning = true
                    } label: {
                        Label("Scan QR", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(working)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Or paste a ticket")
                            .font(.headline)

                        TextField("atman-blob1…", text: $manualTicket)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.go)
                            .focused($ticketFieldFocused)
                            .onSubmit { receive(manualTicket) }

                        Button {
                            pasteAndReceive()
                        } label: {
                            Label("Paste & Receive", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(working)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { ticketFieldFocused = false }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Receive")
            .sheet(isPresented: $scanning) {
                QRScannerSheet { scanResult in
                    scanning = false
                    if case .success(let value) = scanResult {
                        receive(value)
                    }
                }
            }
            .sheet(isPresented: $working) {
                TransferSheet(
                    label: progressLabel,
                    onCancel: {
                        transferTask?.cancel()
                        working = false
                    }
                )
                .presentationDetents([.height(240)])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled()
            }
            .alert(
                resultAlertTitle,
                isPresented: Binding(
                    get: { result != nil },
                    set: { if !$0 { dismissResult() } }
                ),
                presenting: result
            ) { outcome in
                if outcome.photos > 0 {
                    Button("Open Photos") { openPhotos() }
                }
                if outcome.files > 0 {
                    Button("Open Files") { openFiles() }
                }
                Button("Done", role: .cancel) {}
            }
        }
    }

    /// "1.23 MB (450 KB/s)". Rate is a rolling average since transfer start;
    /// hidden for the first ~500ms so the first sample doesn't show a wild
    /// figure.
    private var progressLabel: String {
        let bytes = Self.byteFormatter.string(fromByteCount: Int64(bytesReceived))
        guard bytesReceived > 0, let start = transferStart else { return bytes }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed >= 0.5 else { return bytes }
        let bytesPerSec = Double(bytesReceived) / elapsed
        let rate = Self.byteFormatter.string(fromByteCount: Int64(bytesPerSec))
        return "\(bytes) (\(rate)/s)"
    }

    private var resultAlertTitle: String {
        guard let result else { return "" }
        switch (result.photos, result.files) {
        case (let p, 0): return "Received \(p) photo\(p == 1 ? "" : "s")"
        case (0, let f): return "Received \(f) file\(f == 1 ? "" : "s")"
        case (let p, let f):
            return "Received \(p) photo\(p == 1 ? "" : "s") and \(f) file\(f == 1 ? "" : "s")"
        }
    }

    private func dismissResult() {
        result = nil
        manualTicket = ""
    }

    private func pasteAndReceive() {
        guard let pasted = UIPasteboard.general.string,
            !pasted.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            errorMessage = "Clipboard is empty."
            return
        }
        manualTicket = pasted
        receive(pasted)
    }

    private func openPhotos() {
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
    }

    private func openFiles() {
        // Open Files navigated to this app's Documents directory (which
        // shows up as "On My iPhone → Beam"). Trick: build a URL with the
        // `shareddocuments` scheme and the same path as the Documents
        // file:// URL.
        guard let docs = PhotoSaver.documentsDirectory,
            var components = URLComponents(url: docs, resolvingAgainstBaseURL: false)
        else { return }
        components.scheme = "shareddocuments"
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }

    private func receive(_ ticket: String) {
        let trimmed = ticket.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        result = nil
        bytesReceived = 0
        transferStart = Date()
        working = true

        transferTask = Task.detached {
            do {
                let staging = FileManager.default.temporaryDirectory
                    .appendingPathComponent("beam-staging", isDirectory: true)
                try? FileManager.default.createDirectory(
                    at: staging, withIntermediateDirectories: true)

                let staged = try await AtmanBridge.shared.downloadFiles(
                    ticket: trimmed,
                    into: staging,
                    onProgress: { bytes in
                        Task { @MainActor in bytesReceived = bytes }
                    }
                )
                try Task.checkCancellation()
                let summary = await PhotoSaver.save(stagedFiles: staged)
                await MainActor.run {
                    if summary.photosSaved == 0 && summary.documentsSaved == 0,
                        let first = summary.failures.first
                    {
                        self.errorMessage = first.localizedDescription
                    } else {
                        self.result = SaveOutcome(
                            photos: summary.photosSaved,
                            files: summary.documentsSaved
                        )
                        if let first = summary.failures.first {
                            self.errorMessage = "Some files failed: \(first.localizedDescription)"
                        }
                    }
                    self.working = false
                }
            } catch is CancellationError {
                await MainActor.run { self.working = false }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.working = false
                }
            }
        }
    }
}

/// AirDrop-style transfer modal: circular indeterminate ring + byte
/// counter with rate + prominent Cancel. Dismisses automatically when
/// the parent flips `working` back to `false`.
private struct TransferSheet: View {
    let label: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(2.0)
                .padding(.top, 8)
            Text("Receiving")
                .font(.headline)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button(role: .cancel, action: onCancel) {
                Text("Cancel").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }
}
