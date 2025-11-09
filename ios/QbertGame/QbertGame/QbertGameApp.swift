import SwiftUI
import AVFoundation

@main
struct QbertGameApp: App {
    @StateObject private var coordinator = GameCoordinator()

    var body: some Scene {
        WindowGroup {
            GameView()
                .environmentObject(coordinator)
                .onAppear {
                    coordinator.startMusic()
                }
                .onDisappear {
                    coordinator.stopMusic()
                }
        }
    }
}
