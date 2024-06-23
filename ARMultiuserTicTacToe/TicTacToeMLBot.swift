//
//  TicTacToeMLOpponent.swift
//  ARMultiuserTicTacToe
//
//  Created by Artem Mykytyshyn on 2024-06-22.
//  Copyright © 2024 Apple. All rights reserved.
//

import Foundation
import CoreML

class TicTacToeMLBot {
    private let botMark = NSNumber(integerLiteral: 1)
    private let humanMark = NSNumber(integerLiteral: 0)
    private let emptyMark = NSNumber(integerLiteral: 2)
    private let boardSize = 9
    
    private var boardState: MLMultiArray
    
    private let model: TicTacToeKerasModel
    
    init() {
        do {
            self.model = try TicTacToeKerasModel(configuration: MLModelConfiguration())
        } catch {
            fatalError("Could not initialize the model")
        }
        
        guard let mlArray = try? MLMultiArray(shape: [1, boardSize as NSNumber], dataType: .float32) else {
            fatalError("Could not create ml array")
        }
        
        for i in 0..<boardSize {
            mlArray[i] = emptyMark
        }
        
        self.boardState = mlArray
    }
    
    func move(at position: XOPosition, isBotMove: Bool = true) {
        let mark = isBotMove ? botMark : humanMark
        boardState[position.rawValue] = mark
    }
    
    func bestMove() -> XOPosition? {
        var bestValue = NSNumber(floatLiteral: 0)
        var bestMove: XOPosition? = nil
        
        for position in XOPosition.allCases {
            guard boardState[position.rawValue] == emptyMark else { continue }
            
            guard let newState = copyMLArray(boardState) else { fatalError("failed to copy an MLMultiArray") }
            newState[position.rawValue] = botMark
            
            guard let prediction = try? model.prediction(dense_1_input: newState) else {
                fatalError("prediction failed")
            }
            
            let result = prediction.Identity[0]
            
            if result.floatValue > bestValue.floatValue {
                bestValue = result
                bestMove = position
            }
        }
        
        return bestMove
    }
    
    private func copyMLArray(_ mlArray: MLMultiArray) -> MLMultiArray? {
        let copy = try? MLMultiArray(shape: mlArray.shape, dataType: mlArray.dataType)
        
        for i in 0..<boardSize {
            copy?[i] = mlArray[i]
        }
        
        return copy
    }
    
}
