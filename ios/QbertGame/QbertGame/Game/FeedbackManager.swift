import Foundation
import UIKit

final class FeedbackManager {
    enum Event {
        case jump
        case danger
        case levelComplete
        case lifeLost
    }

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let successGenerator = UINotificationFeedbackGenerator()

    init() {
        lightImpact.prepare()
        heavyImpact.prepare()
        successGenerator.prepare()
    }

    func trigger(event: Event) {
        switch event {
        case .jump:
            lightImpact.impactOccurred(intensity: 0.5)
        case .danger:
            heavyImpact.impactOccurred(intensity: 1.0)
        case .levelComplete:
            successGenerator.notificationOccurred(.success)
        case .lifeLost:
            successGenerator.notificationOccurred(.error)
        }
    }
}
