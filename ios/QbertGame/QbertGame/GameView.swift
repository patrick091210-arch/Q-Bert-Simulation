import SwiftUI
import SpriteKit

struct GameView: View {
    @EnvironmentObject private var coordinator: GameCoordinator
    private let scene = QbertScene(size: CGSize(width: 1080, height: 1920))

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                SpriteView(scene: scene, preferredFramesPerSecond: 60)
                    .ignoresSafeArea()
                VStack {
                    GameHUDView()
                        .padding(.top, 16)
                    Spacer()
                    controlOverlay(width: proxy.size.width)
                        .padding(.bottom, 24)
                }
            }
            .background(Color.black)
            .onAppear {
                scene.size = proxy.size
                coordinator.attach(scene: scene)
            }
        }
    }

    @ViewBuilder
    private func controlOverlay(width: CGFloat) -> some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button(action: coordinator.toggleControlMode) {
                    Label(coordinator.controlMode == .virtualPad ? "切换至滑动" : "切换至按键", systemImage: "arrow.left.arrow.right")
                        .font(.headline)
                        .padding(12)
                        .background(Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)

            switch coordinator.controlMode {
            case .virtualPad:
                VirtualPadView(width: width * 0.7)
                    .environmentObject(coordinator)
            case .gesture:
                GestureControlView()
                    .environmentObject(coordinator)
            }
        }
        .foregroundColor(.white)
    }
}

struct GameHUDView: View {
    @EnvironmentObject private var coordinator: GameCoordinator

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("得分: \(coordinator.score)")
                Spacer()
                Text("回合: \(coordinator.round)")
            }
            .font(.title3.bold())
            .padding(.horizontal, 24)

            HStack(spacing: 12) {
                ForEach(0..<coordinator.lives, id: \.self) { _ in
                    Image(systemName: "figure.wave.circle")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button(action: coordinator.pauseOrResume) {
                    Image(systemName: coordinator.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .padding(10)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 24)
        }
        .foregroundColor(.white)
    }
}

private struct VirtualPadView: View {
    @EnvironmentObject private var coordinator: GameCoordinator
    let width: CGFloat

    private let buttonSize: CGFloat = 72

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Spacer()
                controlButton(direction: .upLeft)
                controlButton(direction: .upRight)
                Spacer()
            }
            HStack(spacing: 16) {
                Spacer()
                controlButton(direction: .downLeft)
                controlButton(direction: .downRight)
                Spacer()
            }
        }
        .frame(width: width)
        .padding()
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func controlButton(direction: QbertScene.Direction) -> some View {
        Button {
            coordinator.handle(direction: direction)
        } label: {
            Text(direction.symbol)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .frame(width: buttonSize, height: buttonSize)
                .background(Color.orange.opacity(0.8))
                .clipShape(Circle())
        }
    }
}

private struct GestureControlView: View {
    @EnvironmentObject private var coordinator: GameCoordinator

    var body: some View {
        VStack(spacing: 12) {
            Text("滑动屏幕进行控制")
                .font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                Text("⬑ ⬏\n⬐ ⬎")
                    .font(.system(size: 36))
            }
            .frame(height: 180)
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        let direction = DirectionMapper.direction(for: value.translation)
                        if let direction {
                            coordinator.handle(direction: direction)
                        }
                    }
            )
        }
        .padding(.horizontal, 24)
    }
}

private enum DirectionMapper {
    static func direction(for translation: CGSize) -> QbertScene.Direction? {
        guard abs(translation.width) > 10 || abs(translation.height) > 10 else { return nil }
        let angle = atan2(translation.height, translation.width)
        switch angle {
        case (-.pi)..<(-.pi/2):
            return .upLeft
        case (-.pi/2)..<0:
            return .upRight
        case 0..<(.pi/2):
            return .downRight
        default:
            return .downLeft
        }
    }
}

private extension QbertScene.Direction {
    var symbol: String {
        switch self {
        case .upLeft: "⬑"
        case .upRight: "⬏"
        case .downLeft: "⬐"
        case .downRight: "⬎"
        }
    }
}
