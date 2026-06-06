import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SendView()
                .tabItem {
                    Label("Send", systemImage: "paperplane")
                }
            ReceiveView()
                .tabItem {
                    Label("Receive", systemImage: "tray.and.arrow.down")
                }
        }
    }
}
