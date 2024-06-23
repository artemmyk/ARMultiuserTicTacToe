//
//  MenuViewController.swift
//  ARMultiuserTicTacToe
//
//  Created by Artem Mykytyshyn on 2024-06-23.
//  Copyright © 2024 Apple. All rights reserved.
//

import UIKit

class MenuViewController: UIViewController {
    
    @IBAction func singlePlayerButtonTapped() {
        presentGameViewController(isSingleGame: true)
    }
    
    @IBAction func multiPlayerButtonTapped() {
        presentGameViewController(isSingleGame: false)
    }
    
    
    private func presentGameViewController(isSingleGame: Bool) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let gameVC = storyboard.instantiateViewController(withIdentifier: "ViewController") as? ViewController {
            gameVC.isSingleGame = isSingleGame
            gameVC.modalPresentationStyle = .fullScreen
            present(gameVC, animated: true, completion: nil)
        }
    }
    
}
