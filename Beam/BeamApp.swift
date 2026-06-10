import SwiftUI

@main
struct BeamApp: App {
    @StateObject private var bootstrap = AtmanBootstrap()

    var body: some Scene {
        WindowGroup {
            switch bootstrap.state {
            case .starting:
                StartingView()
            case .ready:
                ContentView()
            case .failed(let message):
                FailedView(message: message)
            }
        }
    }
}

/// Drives the one-time atman startup. UI hangs on `.starting` until iroh
/// finishes binding the endpoint (a few seconds).
@MainActor
final class AtmanBootstrap: ObservableObject {
    enum State {
        case starting
        case ready
        case failed(String)
    }

    @Published var state: State = .starting

    init() {
        Task.detached { [weak self] in
            do {
                try await AtmanBridge.shared.initializeIfNeeded()
                await MainActor.run { self?.state = .ready }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? String(describing: error)
                await MainActor.run { self?.state = .failed(message) }
            }
        }
    }
}

private struct StartingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Starting…")
                .foregroundStyle(.secondary)
        }
    }
}

private struct FailedView: View {
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Couldn't start Beam")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
