#if DEBUG && os(iOS)
import SwiftUI

/// No network/configuration dependency, exercises the production fullscreen container.
struct PlaybackLayoutHarness: View {
    @StateObject private var store = VODDanmakuStore()
    @State private var fullscreen = false
    @State private var sheet = false
    var body: some View {
        Button("Enter playback") { fullscreen = true }
            .accessibilityIdentifier("enterPlayback")
            .fullScreenCover(isPresented: $fullscreen) {
                FullScreenPlayerView(urlString: "file:///nonexistent-layout-fixture.mp4", onCloseRequested: { fullscreen = false }, title: "Layout fixture")
                    .environmentObject(store)
                    .overlay(alignment: .topTrailing) {
                        HStack {
                            Button("Sheet") { sheet = true }.accessibilityIdentifier("openSheet")
                            Button("Exit") { fullscreen = false }.accessibilityIdentifier("exitPlayback")
                        }.padding()
                    }
                    .sheet(isPresented: $sheet) {
                        NavigationStack {
                            Text("Sheet layout").accessibilityIdentifier("sheetContent")
                                .toolbar { Button("Done") { sheet = false }.accessibilityIdentifier("closeSheet") }
                        }
                    }
            }
    }
}
#endif
