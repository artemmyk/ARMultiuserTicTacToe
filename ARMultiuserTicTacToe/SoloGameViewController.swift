//
//  SoloGameViewController.swift
//  ARMultiuserTicTacToe
//
//  Created by Artem Mykytyshyn on 2024-06-23.
//  Copyright © 2024 Apple. All rights reserved.
//

import UIKit
import ARKit
import RealityKit
import MultipeerConnectivity
import Combine
import SwiftUI

class SoloGameViewController: UIViewController {
    
    @IBOutlet var arView: ARView!
    @IBOutlet weak var messageLabel: MessageLabel!
    @IBOutlet weak var restartButton: UIButton!
    @IBOutlet weak var startButton: UIButton!
    
    let ticTacToeMLBot = TicTacToeMLBot()
    
    let coachingOverlay = ARCoachingOverlayView()
    
    var configuration: ARWorldTrackingConfiguration?
    
    private var isPlayersTurn = false
    private var playersModel: String?
    private var boardValues = [XOPosition: XOModel]()
    private var cancellables: Set<AnyCancellable> = []
    
    var boardEntity: ModelEntity!
    var xEntity: ModelEntity!
    var oEntity: ModelEntity!
    var gameAnchor: AnchorEntity?
    
    var isGameOver = false
    var isLoadingXOEntity = false
    
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
        
        setupCoachingOverlay()
        
        // Prevent the screen from being dimmed to avoid interrupting the AR experience.
        UIApplication.shared.isIdleTimerDisabled = true
        
        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(recognizer:))))
        
        loadBoardEntity()
        loadXModel()
        loadOModel()
        
        messageLabel.displayMessage("Invite others to launch this app to join you.")
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
                
                startGameHandler()
                
                return
            }
            
            guard !isGameOver else { return }
            guard !isLoadingXOEntity else { return }
            
            if isPlayersTurn,
               let entity = arView.entity(at: location) as? ModelEntity,
               let position = XOPosition(rawValue: Int(entity.name)!) {
                addXOEntity(in: entity, at: position, isX: playersModel == AssetReference.x.rawValue)
                sendCommand(Command.placedAt, data: String(position.rawValue))
            }
            
        } else {
            messageLabel.displayMessage("Can't place object - no surface found.\nLook for flat surfaces.")
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
extension SoloGameViewController {
    
    func sendCommand(_ command: Command, data: String? = nil) {
        print("sendCommand(_ command: Command, data: String)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.receiveCommand(command, commandData: data)
        }
                
//        let composedCommand = "\(command.rawValue):\(data ?? "")"
//        if let commandData = composedCommand.data(using: .utf8) {
//            multipeerSession.sendToAllPeers(commandData, reliably: true)
//        }
    }
    
    func receiveCommand(_ command: Command, commandData: String? = nil) {
        switch command {
        case Command.gameStarted:
            ticTacToeMLBot.clearState()
        case Command.placedAt:
            guard !isGameOver else { return }
            
            let placedAtPositionRawValue = Int(commandData!)!
            let placedAt = XOPosition(rawValue: placedAtPositionRawValue)!
            ticTacToeMLBot.move(at: placedAt, isBotMove: false)
            let botMovePosition = ticTacToeMLBot.bestMove()
                        
            if let position = botMovePosition,
               let entity = arView.scene.findEntity(named: String(position.rawValue)) as? ModelEntity {
                DispatchQueue.main.async {
                    self.addXOEntity(in: entity, at: position, isX: self.playersModel != AssetReference.x.rawValue)
                }
                ticTacToeMLBot.move(at: position, isBotMove: true)
            }
        case Command.gameRestarted:
            ticTacToeMLBot.clearState()
        default:
            break
        }
    }
    
}

// MARK: - ARSessionDelegate
extension SoloGameViewController: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        print("session(_ session: ARSession, didAdd anchors: [ARAnchor])")
        
        for anchor in anchors {
            if let participantAnchor = anchor as? ARParticipantAnchor {
                let anchorEntity = AnchorEntity(anchor: participantAnchor)
                
                let coordinateSystem = MeshResource.generateCoordinateSystemAxes()
                anchorEntity.addChild(coordinateSystem)
                
                let color = participantAnchor.sessionIdentifier?.toRandomColor() ?? .white
                let coloredSphere = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.03),
                                                materials: [SimpleMaterial(color: color, isMetallic: true)])
                anchorEntity.addChild(coloredSphere)
                
                arView.scene.addAnchor(anchorEntity)
                
                messageLabel.displayMessage("An opponent has joined. Tap the screen to place the grid.")
            } else if anchor.name == "Anchor for object placement" {
                let anchorEntity = AnchorEntity(anchor: anchor)
                anchorEntity.setScale(SIMD3<Float>(0.002, 0.002, 0.002), relativeTo: anchorEntity)
                
                anchorEntity.addChild(boardEntity)
                
                arView.scene.addAnchor(anchorEntity)
                gameAnchor = anchorEntity
            }
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

// MARK: - ModelEntities
extension SoloGameViewController {
    func loadBoardEntity() {
        print("loadBoardEntity()")
                
        ModelEntity.loadModelAsync(named: AssetReference.board.rawValue)
            .sink(
                receiveCompletion: { completion in },
                receiveValue: { [weak self] entity in
                    guard let self = self else { return }
                    
                    entity.name = AssetReference.board.rawValue
                    entity.generateCollisionShapes(recursive: true)
                    
                    self.boardEntity = entity
                }
            )
            .store(in: &cancellables)
    }
    
    func loadXModel() {
        let modelName = AssetReference.x.rawValue
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
                    
                    self.xEntity = xoEntity
                }
            )
            .store(in: &cancellables)
    }   
    
    func loadOModel() {
        let modelName = AssetReference.o.rawValue
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
                    
                    self.oEntity = xoEntity
                }
            )
            .store(in: &cancellables)
    }
    
    func addXOEntity(in entity: ModelEntity, at position: XOPosition, isX: Bool) {
        print("addXOEntity(in entity: ModelEntity, at position: XOPosition)")
        
        let entityHasNoValue = boardEntity.children.first {
            $0.name == String(position.rawValue)
        }?.children.allSatisfy { $0.name != AssetReference.x.rawValue && $0.name != AssetReference.o.rawValue } ?? false
        
        guard entityHasNoValue else { return }
        isLoadingXOEntity = true
        
        let modelName = (isX ? AssetReference.x : AssetReference.o).rawValue
        let xoEntity = isX ? xEntity!.clone(recursive: false) : oEntity!.clone(recursive: false)
        
        entity.addChild(xoEntity)
        
        self.boardValues[position] = XOModel(isX: isX, entity: xoEntity)
        
        self.isPlayersTurn.toggle()
        messageLabel.displayMessage("It's your\(self.isPlayersTurn ? "" : " opponent's") turn.")
        
        self.checkGameStatus()
        self.isLoadingXOEntity = false
    }
    
    func generateTapEntity(in position: XOPosition) {
        print("generateTapEntity(in position: XOPosition)")
        
        let rectangle = MeshResource.generatePlane(width: Constants.oneThirdBoardSize, depth: Constants.oneThirdBoardSize, cornerRadius: 5)
        let material = UnlitMaterial(color: .clear)
        let tapEntity = ModelEntity(mesh: rectangle, materials: [material])
        
        tapEntity.generateCollisionShapes(recursive: true)
        tapEntity.name = String(position.rawValue)
        tapEntity.position = position.toPositionVector()
        
        boardEntity.addChild(tapEntity)
    }
}

// MARK: - Game State
extension SoloGameViewController {
    @IBAction func startGameHandler() {
        print("startGameHandler()")
        
        startGame()
        
        playersModel = AssetReference.x.rawValue
        isPlayersTurn = true
        sendCommand(Command.gameStarted)
        messageLabel.displayMessage("It's your turn.")
    }
    
    func startGame() {
        print("startGame()")
                
        playersModel = AssetReference.o.rawValue
        isPlayersTurn = false
        startButton.isHidden = true

        XOPosition.allCases.forEach(generateTapEntity)
        messageLabel.displayMessage("It's your opponent's turn.")
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
        isGameOver = false
        
        guard let gameAnchor = gameAnchor else { return }
        arView.scene.removeAnchor(gameAnchor)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self else { return }
            loadBoardEntity()
            self.gameAnchor = nil
        }
        
        messageLabel.displayMessage("Place the grid to start the game.")
    }
    
    func resetTracking() {
        print("resetTracking()")
        
        guard let configuration = arView.session.configuration else { print("A configuration is required"); return }
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    private func endGame() {
        withAnimation {
            isGameOver = true
            messageLabel.displayMessage("It's a tie. You can restart the game by clicking the restart button.")
        }
    }
}

// MARK: - Animation
extension SoloGameViewController {
    private func winGame(positions: [XOPosition]) {
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
        messageLabel.displayMessage("You \(!self.isPlayersTurn ? "won" : "lost"). You can restart the game by clicking the restart button.")
    }
}

// MARK: - Game Logic
extension SoloGameViewController {
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
                winGame(positions: combination)
                return
            }
        }
        
        if boardValues.count == 9 {
            endGame()
            return
        }
    }
}

extension SoloGameViewController: ARCoachingOverlayViewDelegate {
    
    func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        messageLabel.ignoreMessages = true
        messageLabel.isHidden = true
        restartButton.isHidden = true
    }

    func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
        messageLabel.ignoreMessages = false
        restartButton.isHidden = false
    }

    func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
        resetTracking()
    }

    func setupCoachingOverlay() {
        // Set up coaching view
        coachingOverlay.session = arView.session
        coachingOverlay.delegate = self
        coachingOverlay.goal = .tracking
        
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coachingOverlay)
        
        NSLayoutConstraint.activate([
            coachingOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            coachingOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            coachingOverlay.widthAnchor.constraint(equalTo: view.widthAnchor),
            coachingOverlay.heightAnchor.constraint(equalTo: view.heightAnchor)
            ])
    }
}

