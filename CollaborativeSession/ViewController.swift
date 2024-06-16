/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 Main view controller for the AR experience.
 */

import UIKit
import RealityKit
import ARKit
import MultipeerConnectivity
import Combine
import SwiftUI

class ViewController: UIViewController {
    
    @IBOutlet var arView: ARView!
    @IBOutlet weak var messageLabel: MessageLabel!
    @IBOutlet weak var restartButton: UIButton!
    @IBOutlet weak var startButton: UIButton!
    
    var multipeerSession: MultipeerSession?
    
    let coachingOverlay = ARCoachingOverlayView()
    
    // A dictionary to map MultiPeer IDs to ARSession ID's.
    // This is useful for keeping track of which peer created which ARAnchors.
    var peerSessionIDs = [MCPeerID: String]()
    
    var sessionIDObservation: NSKeyValueObservation?
    
    var configuration: ARWorldTrackingConfiguration?
    
    //
    private var isPlayersTurn = false
    private var playersModel: String?
    private var boardValues = [XOPosition: XOModel]()
    private var cancellables: Set<AnyCancellable> = []
    
    var boardEntity: ModelEntity!
    var gameAnchor: AnchorEntity?
    var removeEditBoardGesturesAction: (() -> Void)?
    
    @Published var isGameOver = false
    @Published var isTapScreenPresented = true
    @Published var isAdjustBoardPresented = false
    @Published var isLoadingXOEntity = false
    
    override func viewDidAppear(_ animated: Bool) {
        
        super.viewDidAppear(animated)
        
        arView.session.delegate = self
        
        // Turn off ARView's automatically-configured session
        // to create and set up your own configuration.
        arView.automaticallyConfigureSession = false
        
        configuration = ARWorldTrackingConfiguration()
        
        // Enable a collaborative session.
        configuration?.isCollaborationEnabled = true
        
        // Enable realistic reflections.
        configuration?.environmentTexturing = .automatic
        
        // Enable people occlusion
        configuration?.frameSemantics.insert(.personSegmentationWithDepth)
        
        // Begin the session.
        arView.session.run(configuration!)
        
        // Use key-value observation to monitor your ARSession's identifier.
        sessionIDObservation = observe(\.arView.session.identifier, options: [.new]) { object, change in
            print("SessionID changed to: \(change.newValue!)")
            // Tell all other peers about your ARSession's changed ID, so
            // that they can keep track of which ARAnchors are yours.
            guard let multipeerSession = self.multipeerSession else { return }
            self.sendARSessionIDTo(peers: multipeerSession.connectedPeers)
        }
        
        setupCoachingOverlay()
        
        // Start looking for other players via MultiPeerConnectivity.
        multipeerSession = MultipeerSession(delegate: self)
        
        // Prevent the screen from being dimmed to avoid interrupting the AR experience.
        UIApplication.shared.isIdleTimerDisabled = true
        
        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(recognizer:))))
        
        addBoardEntity(in: arView.scene, arView: arView)
        
        messageLabel.displayMessage("Tap the screen to place the grid.\nInvite others to launch this app to join you.", duration: 60.0)
    }
    
    @objc
    func handleTap(recognizer: UITapGestureRecognizer) {
        print("handleTap(recognizer: UITapGestureRecognizer)")
        
        let location = recognizer.location(in: arView)
        
        let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
        if let firstResult = results.first {
            if gameAnchor == nil {
                let anchor = ARAnchor(name: "Anchor for object placement", transform: firstResult.worldTransform)
                arView.session.add(anchor: anchor)
                
                return
            }
            
            guard isGameOver == false else { return }
            guard isLoadingXOEntity == false else { return }
            if isPlayersTurn,
               let entity = arView.entity(at: location) as? ModelEntity,
               let position = XOPosition(rawValue: entity.name) {
                addXOEntity(in: entity, at: position, isX: playersModel == AssetReference.x.rawValue)
                sendCommand(Command.placedAt, data: position.rawValue)
            }
            
        } else {
            messageLabel.displayMessage("Can't place object - no surface found.\nLook for flat surfaces.", duration: 2.0)
            print("Warning: Object placement failed.")
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        // Request that iOS hide the status bar to improve immersiveness of the AR experience.
        return true
    }
    
    override var prefersHomeIndicatorAutoHidden: Bool {
        // Request that iOS hide the home indicator to improve immersiveness of the AR experience.
        return true
    }
    
    private func removeAllAnchorsOriginatingFromARSessionWithID(_ identifier: String) {
        print("removeAllAnchorsOriginatingFromARSessionWithID(_ identifier: String)")
        
        guard let frame = arView.session.currentFrame else { return }
        for anchor in frame.anchors {
            guard let anchorSessionID = anchor.sessionIdentifier else { continue }
            if anchorSessionID.uuidString == identifier {
                arView.session.remove(anchor: anchor)
            }
        }
    }
    
}

// MARK: - Data Communication
extension ViewController {
    
    private func sendARSessionIDTo(peers: [MCPeerID]) {
        print("sendARSessionIDTo(peers: [MCPeerID])")
        
        guard let multipeerSession = multipeerSession else { return }
        let idString = arView.session.identifier.uuidString
        let command = "SessionID:" + idString
        if let commandData = command.data(using: .utf8) {
            multipeerSession.sendToPeers(commandData, reliably: true, peers: peers)
        }
    }
    
    func sendCommand(_ command: Command, data: String? = nil) {
        print("sendCommand(_ command: Command, data: String)")
        
        guard let multipeerSession = multipeerSession else { return }
        
        let composedCommand = "\(command.rawValue):\(data ?? "")"
        if let commandData = composedCommand.data(using: .utf8) {
            multipeerSession.sendToAllPeers(commandData, reliably: true)
        }
    }
    
}

// MARK: - ARSessionDelegate
extension ViewController: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        print("session(_ session: ARSession, didAdd anchors: [ARAnchor])")
        
        for anchor in anchors {
            if let participantAnchor = anchor as? ARParticipantAnchor {
                messageLabel.displayMessage("Established joint experience with a peer.")
                // ...
                let anchorEntity = AnchorEntity(anchor: participantAnchor)
                
                let coordinateSystem = MeshResource.generateCoordinateSystemAxes()
                anchorEntity.addChild(coordinateSystem)
                
                let color = participantAnchor.sessionIdentifier?.toRandomColor() ?? .white
                let coloredSphere = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.03),
                                                materials: [SimpleMaterial(color: color, isMetallic: true)])
                anchorEntity.addChild(coloredSphere)
                
                arView.scene.addAnchor(anchorEntity)
            } else if anchor.name == "Anchor for object placement" {
                let anchorEntity = AnchorEntity(anchor: anchor)
                anchorEntity.setScale(SIMD3<Float>(0.002, 0.002, 0.002), relativeTo: anchorEntity)
                
                anchorEntity.addChild(boardEntity)
                
                arView.scene.addAnchor(anchorEntity)
                gameAnchor = anchorEntity
                
                withAnimation {
                    isTapScreenPresented = false
                    isAdjustBoardPresented = true
                }
                
                startButton.isHidden = false
            }
        }
    }
    
    /// - Tag: DidOutputCollaborationData
    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        print("session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData)")
        
        guard let multipeerSession = multipeerSession else { return }
        if !multipeerSession.connectedPeers.isEmpty {
            guard let encodedData = try? NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
            else { fatalError("Unexpectedly failed to encode collaboration data.") }
            // Use reliable mode if the data is critical, and unreliable mode if the data is optional.
            let dataIsCritical = data.priority == .critical
            multipeerSession.sendToAllPeers(encodedData, reliably: dataIsCritical)
        } else {
            print("Deferred sending collaboration to later because there are no peers.")
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("session(_ session: ARSession, didFailWithError error: Error)")
        
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            // Present the error that occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetTracking()
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
}

// MARK: - MultipeerSessionDelegate
extension ViewController: MultipeerSessionDelegate {
    func receivedData(_ data: Data, from peer: MCPeerID) {
        print("receivedData(_ data: Data, from peer: MCPeerID)")
        
        if let collaborationData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARSession.CollaborationData.self, from: data) {
            arView.session.update(with: collaborationData)
            return
        }
        
        // handle commands
        guard let commandString = String(data: data, encoding: .utf8) else { return }
        let commandComponents = commandString.components(separatedBy: Constants.commandDataSeparator)
        guard let command = Command(rawValue: commandComponents[0]) else { return }
        let commandData = commandComponents[1]
        
        switch command {
        case Command.sessionID:
            let newSessionID = commandData
            
            if let oldSessionID = peerSessionIDs[peer] {
                removeAllAnchorsOriginatingFromARSessionWithID(oldSessionID)
            }
            
            peerSessionIDs[peer] = newSessionID
            
        case Command.gameStarted:
            DispatchQueue.main.async {
                self.startGame()
            }
            
        case Command.placedAt:
            let placedAtPositionRawValue = commandData
            
            if let position = XOPosition(rawValue: placedAtPositionRawValue),
               let entity = arView.scene.findEntity(named: position.rawValue) as? ModelEntity {
                DispatchQueue.main.async {
                    self.addXOEntity(in: entity, at: position, isX: self.playersModel != AssetReference.x.rawValue)
                }
            }
        case Command.gameRestarted:
            DispatchQueue.main.async {
                self.restartGame()
            }
        }
    }
    
    
    func peerDiscovered(_ peer: MCPeerID) -> Bool {
        print("peerDiscovered(_ peer: MCPeerID) -> Bool")
        
        guard let multipeerSession = multipeerSession else { return false }
        
        if multipeerSession.connectedPeers.count == 2 {
            // Do not accept more than four users in the experience.
            messageLabel.displayMessage("A fifth peer wants to join the experience.\nThis app is limited to two users.", duration: 6.0)
            return false
        } else {
            return true
        }
    }
    /// - Tag: PeerJoined
    func peerJoined(_ peer: MCPeerID) {
        print("peerDiscovered(_ peer: MCPeerID) -> Bool")
        
        messageLabel.displayMessage("""
            A peer wants to join the experience.
            Hold the phones next to each other.
            """, duration: 6.0)
        // Provide your session ID to the new user so they can keep track of your anchors.
        sendARSessionIDTo(peers: [peer])
    }
    
    func peerLeft(_ peer: MCPeerID) {
        print("peerLeft(_ peer: MCPeerID)")
        
        messageLabel.displayMessage("A peer has left the shared experience.")
        
        // Remove all ARAnchors associated with the peer that just left the experience.
        if let sessionID = peerSessionIDs[peer] {
            removeAllAnchorsOriginatingFromARSessionWithID(sessionID)
            peerSessionIDs.removeValue(forKey: peer)
        }
    }
}

// MARK: - ModelEntities
extension ViewController {
    func addBoardEntity(in scene: RealityKit.Scene, arView: ARView) {
        print("addBoardEntity(in scene: RealityKit.Scene, arView: ARView)")
        
        ModelEntity.loadModelAsync(named: AssetReference.board.rawValue)
            .sink(
                receiveCompletion: { completion in },
                receiveValue: { [weak self] entity in
                    guard let self = self else { return }
                    entity.name = AssetReference.board.rawValue
                    entity.generateCollisionShapes(recursive: true)
                    //                    arView.installGestures(.all, for: entity)
                    self.boardEntity = entity
                }
            )
            .store(in: &cancellables)
    }
    
    func addXOEntity(in entity: ModelEntity, at position: XOPosition, isX: Bool) {
        print("addXOEntity(in entity: ModelEntity, at position: XOPosition)")
        
        let entityHasNoValue = boardEntity.children.first {
            $0.name == position.rawValue
        }?.children.allSatisfy { $0.name != AssetReference.x.rawValue && $0.name != AssetReference.o.rawValue } ?? false
        
        guard entityHasNoValue else { return }
        isLoadingXOEntity = true
        
        let modelName = (isX ? AssetReference.x : AssetReference.o).rawValue
        ModelEntity.loadModelAsync(named: modelName)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoadingXOEntity = false
                    
                    switch completion {
                    case .failure(let err): print(err.localizedDescription)
                    default: return
                    }
                },
                receiveValue: { [weak self] xoEntity in
                    guard let self = self else { return }
                    xoEntity.name = modelName
                    entity.addChild(xoEntity)
                    
                    self.boardValues[position] = XOModel(isX: isX, entity: xoEntity)
                    
                    self.checkGameStatus()
                    self.isPlayersTurn.toggle()
                    self.isLoadingXOEntity = false
                    
                }
            )
            .store(in: &cancellables)
    }
    
    
    func generateTapEntity(in position: XOPosition) {
        print("generateTapEntity(in position: XOPosition)")
        
        let rectangle = MeshResource.generatePlane(width: Constants.oneThirdBoardSize, depth: Constants.oneThirdBoardSize, cornerRadius: 5)
        let material = UnlitMaterial(color: .clear)
        let tapEntity = ModelEntity(mesh: rectangle, materials: [material])
        
        tapEntity.generateCollisionShapes(recursive: true)
        tapEntity.name = position.rawValue
        tapEntity.position = position.toPositionVector()
        
        boardEntity.addChild(tapEntity)
    }
}

// MARK: - Game State
extension ViewController {
    @IBAction func startGameHandler() {
        print("startGameHandler()")
        
        startGame()
        playersModel = AssetReference.x.rawValue
        isPlayersTurn = true
        sendCommand(Command.gameStarted)
    }
    
    func startGame() {
        print("startGame()")
                
        playersModel = AssetReference.o.rawValue
        isPlayersTurn = false
        startButton.isHidden = true
        withAnimation { isAdjustBoardPresented = false }
        XOPosition.allCases.forEach(generateTapEntity)
        //        removeEditBoardGesturesAction?()
    }
    
    @IBAction func restartGameHandler() {
        print("restartGameHandler()")
        
        restartGame()
        sendCommand(Command.gameRestarted)
    }
    
    func restartGame() {
        print("restartGame()")
        
        playersModel = AssetReference.o.rawValue
        isPlayersTurn = false
        boardValues.removeAll()
        withAnimation {
            isGameOver = false
            isAdjustBoardPresented = false
            isTapScreenPresented = true
        }
        
        guard let gameAnchor = gameAnchor else { return }
        arView.scene.removeAnchor(gameAnchor)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self else { return }
            addBoardEntity(in: arView.scene, arView: arView)
            self.gameAnchor = nil
        }
    }
    
    func resetTracking() {
        print("resetTracking()")
        
        guard let configuration = arView.session.configuration else { print("A configuration is required"); return }
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    private func endGame() {
        withAnimation { isGameOver = true }
    }
}

// MARK: - Animation
extension ViewController {
    private func animateEntities(positions: [XOPosition]) {
        for position in positions {
            guard let xoEntity = boardValues[position]?.entity else { continue }
            let isEntityX = xoEntity.name == AssetReference.x.rawValue
            
            var translation = xoEntity.transform
            translation.translation = SIMD3(SCNVector3(0, isEntityX ? 14 : 18, 0))
            xoEntity.move(to: translation, relativeTo: xoEntity.parent, duration: 0.3, timingFunction: .easeInOut)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                var rotation = xoEntity.transform
                rotation.rotation = simd_quatf(angle: .pi/2, axis: [1,0,0])
                xoEntity.move(to: rotation, relativeTo: xoEntity.parent, duration: 0.3, timingFunction: .easeInOut)
            }
        }
        
        endGame()
    }
}

// MARK: - Game Logic
extension ViewController {
    private func checkGameStatus() {
        let winningCombinations: [[XOPosition]] = [
            [.topLeft, .topCenter, .topRight],
            [.centerLeft, .centerCenter, .centerRight],
            [.bottomLeft, .bottomCenter, .bottomRight],
            [.topLeft, .centerLeft, .bottomLeft],
            [.topCenter, .centerCenter, .bottomCenter],
            [.topRight, .centerRight, .bottomRight],
            [.topLeft, .centerCenter, .bottomRight],
            [.topRight, .centerCenter, .bottomLeft]
        ]
        
        for combination in winningCombinations {
            let values = combination.map { boardValues[$0]?.isX }
            if values.allSatisfy({ $0 == true }) || values.allSatisfy({ $0 == false }) {
                animateEntities(positions: combination)
                return
            }
        }
        
        if boardValues.count == 9 {
            endGame()
            return
        }
    }
}
