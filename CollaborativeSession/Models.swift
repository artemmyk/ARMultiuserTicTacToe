//
//  Models.swift
//  CollaborativeSession
//
//  Created by Artem Mykytyshyn on 2024-06-15.
//  Used code from https://github.com/DKabashi/TicTacToeAR/tree/main
//  Copyright © 2024 Apple. All rights reserved.
//

import Foundation
import RealityKit

struct XOModel {
    var isX: Bool
    var entity: ModelEntity
}

enum XOPosition: String, CaseIterable {
    case topLeft, topCenter, topRight,
         centerLeft, centerCenter, centerRight,
         bottomLeft, bottomCenter, bottomRight
    
    func toPositionVector() -> SIMD3<Float> {
        var xPos: BoardPosition!
        var zPos: BoardPosition!
        
        switch self {
        case .topLeft:
            xPos = .xLeft
            zPos = .zLeft
        case .topCenter:
            xPos = .xCenter
            zPos = .zLeft
        case .topRight:
            xPos = .xRight
            zPos = .zLeft
        case .centerLeft:
            xPos = .xLeft
            zPos = .zCenter
        case .centerCenter:
            xPos = .xCenter
            zPos = .zCenter
        case .centerRight:
            xPos = .xRight
            zPos = .zCenter
        case .bottomLeft:
            xPos = .xLeft
            zPos = .zRight
        case .bottomCenter:
            xPos = .xCenter
            zPos = .zRight
        case .bottomRight:
            xPos = .xRight
            zPos = .zRight
        }
        
        return [xPos.rawValue, 0, zPos.rawValue]
    }
}

/// Coordinates to position the entity inside the ttt_board.usdz
enum BoardPosition: Float {
    case xLeft = -46, xCenter = 0.274, xRight = 46,
         zLeft = -44, zCenter = 3, zRight = 51
}

enum AssetReference: String {
    case board = "Board", x = "XMarker", o = "OMarker"
}

enum Command: String {
    case sessionID = "SessionID",
         placedAt = "PlacedAt",
         gameStarted = "GameStarted",
         gameRestarted = "GameRestarted"
}

struct Constants {
    static let boardSize: Float = 136.98
    static let oneThirdBoardSize: Float = 45.66
    
    static let commandDataSeparator  = ":"
}
