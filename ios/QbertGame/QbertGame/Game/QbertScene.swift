import SpriteKit
import UIKit

protocol QbertSceneDelegate: AnyObject {
    func scene(_ scene: QbertScene, didUpdateScore score: Int)
    func scene(_ scene: QbertScene, didUpdateRound round: Int)
    func scene(_ scene: QbertScene, didUpdateLives lives: Int)
    func sceneRequestedFeedback(_ scene: QbertScene, event: FeedbackManager.Event)
}

final class QbertScene: SKScene, SKPhysicsContactDelegate {
    enum Direction: CaseIterable {
        case upLeft, upRight, downLeft, downRight
    }

    struct PhysicsCategory {
        static let qbert: UInt32 = 0x1 << 0
        static let enemy: UInt32 = 0x1 << 1
        static let disk: UInt32 = 0x1 << 2
    }

    struct TileIndex: Hashable {
        let row: Int
        let column: Int
    }

    weak var gameDelegate: QbertSceneDelegate?

    private let rows = 7
    private var tiles: [[TileNode]] = []
    private var disks: [DiskNode] = []
    private var qbert = QbertNode()
    private var qbertTile = TileIndex(row: 0, column: 0)
    private var pendingMoves: [Direction] = []
    private var isJumping = false
    private var lastUpdateTime: TimeInterval = 0
    private var spawnAccumulator: TimeInterval = 0

    private var score: Int = 0 {
        didSet { gameDelegate?.scene(self, didUpdateScore: score) }
    }
    private var round: Int = 1 {
        didSet { gameDelegate?.scene(self, didUpdateRound: round) }
    }
    private var lives: Int = 3 {
        didSet { gameDelegate?.scene(self, didUpdateLives: lives) }
    }

    private var enemies: [EnemyNode] = []
    private var enemySpawnTimer: TimeInterval = 0
    private var slickSamTimer: TimeInterval = 12

    override func didMove(to view: SKView) {
        physicsWorld.contactDelegate = self
        backgroundColor = UIColor(red: 16/255, green: 12/255, blue: 38/255, alpha: 1)
        setupScene()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !isPaused else { return }
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        let delta = currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        spawnAccumulator += delta
        enemySpawnTimer += delta
        slickSamTimer -= delta

        if enemySpawnTimer > max(2.5 - Double(round) * 0.25, 1.2) {
            spawnRandomEnemy()
            enemySpawnTimer = 0
        }

        if slickSamTimer < 0 {
            spawnSlickOrSam()
            slickSamTimer = 14
        }

        for enemy in enemies {
            enemy.update(deltaTime: delta, scene: self)
        }
    }

    func queueMovement(_ direction: Direction) {
        pendingMoves.append(direction)
        processNextMovement()
    }

    private func processNextMovement() {
        guard !isJumping, let direction = pendingMoves.first else { return }
        pendingMoves.removeFirst()
        jump(to: direction)
    }

    private func setupScene() {
        removeAllChildren()
        tiles.removeAll()
        disks.removeAll()

        createStarfield()
        buildPyramid()
        placeDisks()
        addChild(qbert)
        moveQbert(to: TileIndex(row: 0, column: 0), instantly: true)
        score = 0
        round = 1
        lives = 3
        spawnAccumulator = 0
        enemies.removeAll()
    }

    private func createStarfield() {
        let starEmitter = SKEmitterNode()
        starEmitter.particleTexture = SKTexture(image: UIImage(systemName: "star.fill")!.withTintColor(.white))
        starEmitter.particleBirthRate = 1
        starEmitter.particleLifetime = 30
        starEmitter.particleSpeed = -20
        starEmitter.particleAlpha = 0.25
        starEmitter.particleScale = 0.2
        starEmitter.position = CGPoint(x: size.width / 2, y: size.height)
        starEmitter.particlePositionRange = CGVector(dx: size.width, dy: 0)
        addChild(starEmitter)
    }

    private func buildPyramid() {
        let tileSize = min(size.width, size.height) / 10
        let startX = size.width / 2
        let startY = size.height * 0.65

        for row in 0..<rows {
            var rowTiles: [TileNode] = []
            for column in 0...row {
                let tile = TileNode(row: row, column: column, size: tileSize)
                let offsetX = CGFloat(row - column * 2) * tileSize / 2
                let position = CGPoint(x: startX + offsetX, y: startY - CGFloat(row) * tileSize * 0.88)
                tile.position = position
                addChild(tile)
                rowTiles.append(tile)
            }
            tiles.append(rowTiles)
        }
    }

    private func placeDisks() {
        guard let bottomRow = tiles.last else { return }
        let tileSize = bottomRow.first?.tileSize ?? 64
        let positions: [CGPoint] = [
            CGPoint(x: bottomRow.first!.position.x - tileSize * 1.4, y: bottomRow.first!.position.y + tileSize * 0.4),
            CGPoint(x: bottomRow.last!.position.x + tileSize * 1.4, y: bottomRow.last!.position.y + tileSize * 0.4)
        ]

        for side in DiskNode.Side.allCases {
            let disk = DiskNode(side: side, radius: tileSize * 0.5)
            disk.position = positions[side.rawValue]
            addChild(disk)
            disks.append(disk)
        }
    }

    private func jump(to direction: Direction) {
        guard let target = targetIndex(from: qbertTile, direction: direction) else {
            fallFromPyramid()
            return
        }

        guard let tile = tile(at: target) else {
            fallFromPyramid()
            return
        }

        isJumping = true
        gameDelegate?.sceneRequestedFeedback(self, event: .jump)

        let path = CGMutablePath()
        let start = qbert.position
        let control = CGPoint(x: (start.x + tile.position.x) / 2, y: max(start.y, tile.position.y) + 80)
        path.move(to: start)
        path.addQuadCurve(to: tile.position, control: control)
        let action = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 0.2)
        qbert.run(action) { [weak self] in
            guard let self else { return }
            self.qbertTile = target
            tile.advance(round: self.round, score: &self.score)
            self.checkLevelProgress()
            self.isJumping = false
            self.processNextMovement()
        }
    }

    private func moveQbert(to tileIndex: TileIndex, instantly: Bool) {
        guard let tile = tile(at: tileIndex) else { return }
        qbertTile = tileIndex
        if instantly {
            qbert.position = tile.position
        } else {
            qbert.run(SKAction.move(to: tile.position, duration: 0.15))
        }
    }

    func targetIndex(from index: TileIndex, direction: Direction) -> TileIndex? {
        switch direction {
        case .upLeft:
            let newIndex = TileIndex(row: index.row - 1, column: index.column - 1)
            return newIndex.row >= 0 && newIndex.column >= 0 && newIndex.column <= newIndex.row ? newIndex : nil
        case .upRight:
            let newIndex = TileIndex(row: index.row - 1, column: index.column)
            return newIndex.row >= 0 && newIndex.column >= 0 && newIndex.column <= newIndex.row ? newIndex : nil
        case .downLeft:
            let newIndex = TileIndex(row: index.row + 1, column: index.column)
            return newIndex.row < rows && newIndex.column >= 0 && newIndex.column <= newIndex.row ? newIndex : nil
        case .downRight:
            let newIndex = TileIndex(row: index.row + 1, column: index.column + 1)
            return newIndex.row < rows && newIndex.column >= 0 && newIndex.column <= newIndex.row ? newIndex : nil
        }
    }

    private func tile(at index: TileIndex) -> TileNode? {
        guard index.row >= 0 && index.row < tiles.count else { return nil }
        let row = tiles[index.row]
        guard index.column >= 0 && index.column < row.count else { return nil }
        return row[index.column]
    }

    private func fallFromPyramid() {
        isJumping = true
        let fallAction = SKAction.sequence([
            SKAction.group([
                SKAction.move(by: CGVector(dx: 0, dy: -size.height), duration: 0.8),
                SKAction.rotate(byAngle: -.pi, duration: 0.8)
            ]),
            SKAction.run { [weak self] in
                self?.resolveLifeLost()
            }
        ])
        qbert.run(fallAction)
        gameDelegate?.sceneRequestedFeedback(self, event: .danger)
    }

    private func resolveLifeLost() {
        lives -= 1
        gameDelegate?.sceneRequestedFeedback(self, event: .lifeLost)
        if lives <= 0 {
            resetGame()
        } else {
            qbert.removeAllActions()
            moveQbert(to: TileIndex(row: 0, column: 0), instantly: true)
            isJumping = false
            pendingMoves.removeAll()
        }
    }

    private func checkLevelProgress() {
        let unfinished = tiles.flatMap { $0 }.contains { !$0.isComplete }
        if !unfinished {
            round += 1
            gameDelegate?.sceneRequestedFeedback(self, event: .levelComplete)
            advanceLevel()
        }
    }

    private func advanceLevel() {
        for tile in tiles.flatMap({ $0 }) {
            tile.reset(for: round)
        }
        moveQbert(to: TileIndex(row: 0, column: 0), instantly: false)
        pendingMoves.removeAll()
        enemies.forEach { $0.removeFromParent() }
        enemies.removeAll()
    }

    private func resetGame() {
        round = 1
        score = 0
        lives = 3
        for tile in tiles.flatMap({ $0 }) {
            tile.reset(for: round)
        }
        moveQbert(to: TileIndex(row: 0, column: 0), instantly: true)
        pendingMoves.removeAll()
        enemies.forEach { $0.removeFromParent() }
        enemies.removeAll()
        isJumping = false
    }

    private func spawnRandomEnemy() {
        guard let startTile = tiles.first?.first else { return }
        let typeRoll = Int.random(in: 0...100)
        let enemy: EnemyNode
        if typeRoll < 35 {
            enemy = RedBall()
        } else if typeRoll < 65 {
            enemy = GreenBall()
        } else {
            enemy = Coily()
        }
        enemy.configure(in: self)
        addChild(enemy)
        enemies.append(enemy)
        enemy.start(on: TileIndex(row: 0, column: 0), scene: self, qbertTile: qbertTile)
    }

    private func spawnSlickOrSam() {
        let enemy: EnemyNode = Bool.random() ? Slick() : Sam()
        enemy.configure(in: self)
        addChild(enemy)
        enemies.append(enemy)
        if let startRow = tiles.dropFirst(2).first {
            if let startTile = startRow.randomElement() {
                enemy.start(on: TileIndex(row: startTile.row, column: startTile.column), scene: self, qbertTile: qbertTile)
            }
        }
    }

    func move(enemy: EnemyNode, to index: TileIndex) {
        guard let tile = tile(at: index) else { return }
        enemy.currentIndex = index
        let move = SKAction.move(to: tile.position, duration: enemy.movementDuration)
        enemy.run(move)
    }

    func position(for index: TileIndex) -> CGPoint? {
        tile(at: index)?.position
    }

    func qbertTilePosition() -> TileIndex { qbertTile }

    func reachedDisk(on side: DiskNode.Side) {
        score += 500
        gameDelegate?.sceneRequestedFeedback(self, event: .levelComplete)
        moveQbert(to: TileIndex(row: 0, column: 0), instantly: false)
    }

    func enemyDidReachQbert(_ enemy: EnemyNode) {
        enemy.removeAllActions()
        enemy.removeFromParent()
        enemies.removeAll { $0 === enemy }
        resolveLifeLost()
    }

    func enemyEscaped(_ enemy: EnemyNode) {
        enemy.removeAllActions()
        enemy.removeFromParent()
        enemies.removeAll { $0 === enemy }
    }

    func slickOrSamTouched(_ enemy: EnemyNode) {
        guard let slick = enemy as? SlickSamReverter else { return }
        slick.revertTiles(scene: self)
        enemyEscaped(enemy)
    }

    func collectGreenBall(_ enemy: EnemyNode) {
        score += 100
        enemyEscaped(enemy)
    }

    func resetTileColorsToDefault() {
        for tile in tiles.flatMap({ $0 }) {
            tile.revert()
        }
    }

    // MARK: - SKPhysicsContactDelegate

    func didBegin(_ contact: SKPhysicsContact) {
        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if categories == PhysicsCategory.qbert | PhysicsCategory.enemy {
            if let enemy = contact.bodyA.node as? EnemyNode ?? contact.bodyB.node as? EnemyNode {
                switch enemy.interaction {
                case .harmful:
                    enemyDidReachQbert(enemy)
                    gameDelegate?.sceneRequestedFeedback(self, event: .danger)
                case .revert:
                    slickOrSamTouched(enemy)
                case .beneficial:
                    collectGreenBall(enemy)
                }
            }
        } else if categories == PhysicsCategory.qbert | PhysicsCategory.disk {
            if let disk = contact.bodyA.node as? DiskNode ?? contact.bodyB.node as? DiskNode {
                disk.use(scene: self)
            }
        }
    }
}

// MARK: - Tile Node

private final class TileNode: SKShapeNode {
    private(set) var row: Int
    private(set) var column: Int
    let tileSize: CGFloat
    private var colors: [UIColor] = []
    private(set) var currentStep: Int = 0
    private var targetSteps: Int = 1

    var isComplete: Bool { currentStep >= targetSteps }

    init(row: Int, column: Int, size: CGFloat) {
        self.row = row
        self.column = column
        self.tileSize = size
        super.init()

        let path = UIBezierPath()
        let half = size / 2
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: half, y: half * 0.9))
        path.addLine(to: CGPoint(x: -half, y: half * 0.9))
        path.close()
        self.path = path.cgPath

        fillColor = UIColor(red: 0.28, green: 0.58, blue: 0.92, alpha: 1)
        strokeColor = UIColor.white
        lineWidth = 2
        zPosition = CGFloat(row)

        physicsBody = SKPhysicsBody(polygonFrom: path.cgPath)
        physicsBody?.isDynamic = false
        physicsBody?.categoryBitMask = 0
        physicsBody?.contactTestBitMask = 0
        configureColors(for: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func advance(round: Int, score: inout Int) {
        targetSteps = min(2 + round / 3, 3)
        configureColors(for: round)
        if currentStep < targetSteps {
            currentStep += 1
            fillColor = colors[min(currentStep, colors.count - 1)]
            score += 25 * currentStep
        }
    }

    func reset(for round: Int) {
        currentStep = 0
        configureColors(for: round)
        fillColor = colors.first ?? .cyan
    }

    func revert() {
        currentStep = max(0, currentStep - 1)
        fillColor = colors[min(currentStep, colors.count - 1)]
    }

    private func configureColors(for round: Int) {
        colors = [
            UIColor(red: 0.19, green: 0.94, blue: 0.75, alpha: 1),
            UIColor(red: 0.96, green: 0.64, blue: 0.14, alpha: 1),
            UIColor(red: 0.83, green: 0.16, blue: 0.36, alpha: 1)
        ]
        if round > 2 {
            colors.reverse()
        }
    }
}

// MARK: - Disk

private final class DiskNode: SKShapeNode {
    enum Side: Int, CaseIterable { case left, right }
    private let side: Side
    private var isActive = true

    init(side: Side, radius: CGFloat) {
        self.side = side
        super.init()

        let circle = UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        path = circle.cgPath
        fillColor = UIColor(red: 0.96, green: 0.94, blue: 0.29, alpha: 1)
        strokeColor = UIColor.white
        lineWidth = 2
        zPosition = 100

        physicsBody = SKPhysicsBody(circleOfRadius: radius)
        physicsBody?.isDynamic = false
        physicsBody?.categoryBitMask = QbertScene.PhysicsCategory.disk
        physicsBody?.contactTestBitMask = QbertScene.PhysicsCategory.qbert
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func use(scene: QbertScene) {
        guard isActive else { return }
        isActive = false
        run(SKAction.sequence([
            SKAction.scale(to: 1.3, duration: 0.1),
            SKAction.scale(to: 0.1, duration: 0.25),
            SKAction.removeFromParent(),
            SKAction.run { [weak scene] in
                guard let scene else { return }
                scene.reachedDisk(on: self.side)
            }
        ]))
    }
}

// MARK: - Qbert Node

private final class QbertNode: SKShapeNode {
    override init() {
        super.init()
        let radius: CGFloat = 28
        path = UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)).cgPath
        fillColor = UIColor.orange
        strokeColor = UIColor.black
        lineWidth = 4
        zPosition = 200

        let eye = SKShapeNode(circleOfRadius: 6)
        eye.position = CGPoint(x: 10, y: 12)
        eye.fillColor = .white
        eye.strokeColor = .black
        eye.zPosition = 205
        addChild(eye)

        let pupil = SKShapeNode(circleOfRadius: 3)
        pupil.fillColor = .black
        pupil.position = CGPoint(x: 10, y: 12)
        pupil.zPosition = 210
        addChild(pupil)

        physicsBody = SKPhysicsBody(circleOfRadius: radius)
        physicsBody?.allowsRotation = false
        physicsBody?.affectedByGravity = false
        physicsBody?.categoryBitMask = QbertScene.PhysicsCategory.qbert
        physicsBody?.contactTestBitMask = QbertScene.PhysicsCategory.enemy | QbertScene.PhysicsCategory.disk
        physicsBody?.collisionBitMask = 0
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Enemies

private class EnemyNode: SKShapeNode {
    enum Interaction {
        case harmful
        case beneficial
        case revert
    }

    var interaction: Interaction { .harmful }
    var movementDuration: TimeInterval = 0.35
    var currentIndex = QbertScene.TileIndex(row: 0, column: 0)
    fileprivate var movementAccumulator: TimeInterval = 0

    func configure(in scene: QbertScene) {
        lineWidth = 3
        strokeColor = .black
        zPosition = 150

        physicsBody = SKPhysicsBody(circleOfRadius: 24)
        physicsBody?.affectedByGravity = false
        physicsBody?.categoryBitMask = QbertScene.PhysicsCategory.enemy
        physicsBody?.contactTestBitMask = QbertScene.PhysicsCategory.qbert
        physicsBody?.collisionBitMask = 0
    }

    func start(on tile: QbertScene.TileIndex, scene: QbertScene, qbertTile: QbertScene.TileIndex) {
        currentIndex = tile
        if let position = scene.position(for: tile) {
            self.position = position
        }
    }

    func update(deltaTime: TimeInterval, scene: QbertScene) {
        movementAccumulator += deltaTime
        guard movementAccumulator >= movementDuration else { return }
        movementAccumulator = 0
        // Default enemies follow gravity downwards
        let options: [QbertScene.Direction] = [.downLeft, .downRight]
        if let direction = options.randomElement(), let next = scene.targetIndex(from: currentIndex, direction: direction) {
            scene.move(enemy: self, to: next)
        } else {
            scene.enemyEscaped(self)
        }
    }
}

private final class RedBall: EnemyNode {
    override init() {
        super.init()
        fillColor = UIColor(red: 0.86, green: 0.2, blue: 0.24, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class GreenBall: EnemyNode {
    override var interaction: Interaction { .beneficial }

    override init() {
        super.init()
        fillColor = UIColor(red: 0.32, green: 0.85, blue: 0.32, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private protocol SlickSamReverter {
    func revertTiles(scene: QbertScene)
}

private final class Slick: EnemyNode, SlickSamReverter {
    override var interaction: Interaction { .revert }

    override init() {
        super.init()
        fillColor = UIColor(red: 0.5, green: 0.91, blue: 0.15, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func revertTiles(scene: QbertScene) {
        scene.resetTileColorsToDefault()
    }
}

private final class Sam: EnemyNode, SlickSamReverter {
    override var interaction: Interaction { .revert }

    override init() {
        super.init()
        fillColor = UIColor(red: 0.96, green: 0.76, blue: 0.18, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func revertTiles(scene: QbertScene) {
        scene.resetTileColorsToDefault()
    }
}

private final class Coily: EnemyNode {
    private enum State {
        case egg
        case snake
    }

    private var state: State = .egg
    private var hatchTimer: TimeInterval = 1.5

    override init() {
        super.init()
        fillColor = UIColor(red: 0.44, green: 0.2, blue: 0.72, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime: TimeInterval, scene: QbertScene) {
        hatchTimer -= deltaTime
        if state == .egg {
            super.update(deltaTime: deltaTime, scene: scene)
            if hatchTimer <= 0 {
                state = .snake
                fillColor = UIColor(red: 0.62, green: 0.28, blue: 0.82, alpha: 1)
                movementDuration = 0.25
                movementAccumulator = 0
            }
            return
        }

        let target = scene.qbertTilePosition()
        var bestDirection: QbertScene.Direction?
        var bestDistance = Double.infinity

        for direction in QbertScene.Direction.allCases {
            guard let next = scene.targetIndex(from: currentIndex, direction: direction) else { continue }
            guard let tilePosition = scene.position(for: next) else { continue }
            let dx = Double(tilePosition.x - (scene.position(for: currentIndex)?.x ?? 0))
            let dy = Double(tilePosition.y - (scene.position(for: currentIndex)?.y ?? 0))
            let distance = hypot(Double(next.row - target.row), Double(next.column - target.column)) + hypot(dx, dy) * 0.001
            if distance < bestDistance {
                bestDistance = distance
                bestDirection = direction
            }
        }

        if let direction = bestDirection, let next = scene.targetIndex(from: currentIndex, direction: direction) {
            scene.move(enemy: self, to: next)
        }
    }
}
