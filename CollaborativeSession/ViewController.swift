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

class ViewController: UIViewController, ARSessionDelegate {
    
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
    private var isXTurn = true
    private var boardValues = [XOPosition: XOModel]()
    private var cancellables: Set<AnyCancellable> = []
    
    var boardEntity: ModelEntity!
    var gameAnchor: AnchorEntity?
    var restartGameAction: (() -> Void)?
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
        multipeerSession = MultipeerSession(receivedDataHandler: receivedData, peerJoinedHandler:
                                            peerJoined, peerLeftHandler: peerLeft, peerDiscoveredHandler: peerDiscovered)
        
        // Prevent the screen from being dimmed to avoid interrupting the AR experience.
        UIApplication.shared.isIdleTimerDisabled = true

        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(recognizer:))))
        
        addBoardEntity(in: arView.scene, arView: arView)
        
        messageLabel.displayMessage("Tap the screen to place cubes.\nInvite others to launch this app to join you.", duration: 60.0)
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
            if let entity = arView.entity(at: location) as? ModelEntity, let position = XOPosition(rawValue: entity.name) {
                addXOEntity(in: entity, at: position)
                sendEntityPlacementData(position: position)
            }

        } else {
            messageLabel.displayMessage("Can't place object - no surface found.\nLook for flat surfaces.", duration: 2.0)
            print("Warning: Object placement failed.")
        }
    }
    
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

                anchorEntity.addChild(self.boardEntity)
                
                arView.scene.addAnchor(anchorEntity)
                gameAnchor = anchorEntity
                
                withAnimation {
                    isTapScreenPresented = false
                    isAdjustBoardPresented = true
                }
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

    func receivedData(_ data: Data, from peer: MCPeerID) {
        print("receivedData(_ data: Data, from peer: MCPeerID)")

        if let collaborationData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARSession.CollaborationData.self, from: data) {
            arView.session.update(with: collaborationData)
            return
        }
        
        guard let commandString = String(data: data, encoding: .utf8) else { return }

        // Handle session ID updates
        let sessionIDCommandString = "SessionID:"
        if commandString.starts(with: sessionIDCommandString) {
            let newSessionID = String(commandString[commandString.index(commandString.startIndex,
                                                                     offsetBy: sessionIDCommandString.count)...])
            if let oldSessionID = peerSessionIDs[peer] {
                removeAllAnchorsOriginatingFromARSessionWithID(oldSessionID)
            }
            
            peerSessionIDs[peer] = newSessionID
        }
        
        // Handle entity placement data
        let placedAtCommandString = "PlacedAt:"
        if commandString.starts(with: placedAtCommandString) {
            let placedAtPositionRawValue = String(commandString[commandString.index(commandString.startIndex, offsetBy: placedAtCommandString.count)...])
            if let position = XOPosition(rawValue: placedAtPositionRawValue),
               let entity = arView.scene.findEntity(named: position.rawValue) as? ModelEntity {
                DispatchQueue.main.async {
                    self.addXOEntity(in: entity, at: position)
                }
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
    
    @IBAction func resetTracking() {
        print("resetTracking()")
        
        guard let configuration = arView.session.configuration else { print("A configuration is required"); return }
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
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
    
    func sendEntityPlacementData(position: XOPosition) {
        print("sendEntityPlacementData(position: XOPosition)")
        
        guard let multipeerSession = multipeerSession else { return }
        let command = "PlacedAt:" + position.rawValue
        if let commandData = command.data(using: .utf8) {
            multipeerSession.sendToAllPeers(commandData, reliably: true)
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
    
    func addXOEntity(in entity: ModelEntity, at position: XOPosition) {
        print("addXOEntity(in entity: ModelEntity, at position: XOPosition)")

        let entityHasNoValue = boardEntity.children.first {
            $0.name == position.rawValue
        }?.children.allSatisfy { $0.name != AssetReference.x.rawValue && $0.name != AssetReference.o.rawValue } ?? false

        guard entityHasNoValue else { return }
        isLoadingXOEntity = true
        
        ModelEntity.loadModelAsync(named: (isXTurn ? AssetReference.x : AssetReference.o).rawValue)
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
                    xoEntity.name = (self.isXTurn ? AssetReference.x : AssetReference.o).rawValue
                    entity.addChild(xoEntity)
                    
                    self.boardValues[position] = XOModel(isX: self.isXTurn, entity: xoEntity)
                    
//                    self.checkGameStatus()
                    self.isXTurn.toggle()
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

// MARK: - Game Logic
extension ViewController {
    @IBAction func startGame() {
        print("startGame()")
        
        startButton.isHidden = true
//        withAnimation { isAdjustBoardPresented = false }
        XOPosition.allCases.forEach(generateTapEntity)
//        removeEditBoardGesturesAction?()
    }
}
