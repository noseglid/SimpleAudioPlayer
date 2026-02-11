import SwiftUI

@main
struct SimpleAudioPlayerApp: App {
    @StateObject private var audioPlayer = AudioPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioPlayer)
                .onAppear {
                }
        }
    }
}
