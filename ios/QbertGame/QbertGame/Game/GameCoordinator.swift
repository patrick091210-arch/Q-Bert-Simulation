import Foundation
import SpriteKit

final class GameCoordinator: ObservableObject {
    enum ControlMode: String, CaseIterable {
        case virtualPad = "虚拟按键"
        case gesture = "滑动手势"
    }

    @Published var controlMode: ControlMode = .virtualPad
    @Published var isPaused: Bool = false
    @Published var score: Int = 0
    @Published var round: Int = 1
    @Published var lives: Int = 3

    private let feedback = FeedbackManager()
    private let musicPlayer = EightBitMusicPlayer()
    private weak var scene: QbertScene?

    func attach(scene: QbertScene) {
        self.scene = scene
        scene.gameDelegate = self
        scene.scaleMode = .resizeFill
    }

    func toggleControlMode() {
        controlMode = controlMode == .virtualPad ? .gesture : .virtualPad
    }

    func handle(direction: QbertScene.Direction) {
        scene?.queueMovement(direction)
    }

    func vibrate(for event: FeedbackManager.Event) {
        feedback.trigger(event: event)
    }

    func startMusic() {
        musicPlayer.startLoop()
    }

    func stopMusic() {
        musicPlayer.stop()
    }

    func pauseOrResume() {
        guard let scene else { return }
        scene.isPaused.toggle()
        isPaused = scene.isPaused
    }
}

extension GameCoordinator: QbertSceneDelegate {
    func scene(_ scene: QbertScene, didUpdateScore score: Int) {
        DispatchQueue.main.async {
            self.score = score
        }
    }

    func scene(_ scene: QbertScene, didUpdateRound round: Int) {
        DispatchQueue.main.async {
            self.round = round
        }
    }

    func scene(_ scene: QbertScene, didUpdateLives lives: Int) {
        DispatchQueue.main.async {
            self.lives = lives
        }
    }

    func sceneRequestedFeedback(_ scene: QbertScene, event: FeedbackManager.Event) {
        vibrate(for: event)
    }
}
