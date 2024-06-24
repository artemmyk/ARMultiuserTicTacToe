//
//  GameModeViewController.swift
//  ARMultiuserTicTacToe
//
//  Created by Artem Mykytyshyn on 2024-06-23.
//  Copyright © 2024 Apple. All rights reserved.
//

import UIKit

protocol GameModeSelectionDelegate: AnyObject {
    func didSelectGameMode(isSinglePlayer: Bool)
}

class GameModeViewController: UIViewController, UIPopoverPresentationControllerDelegate {
    
    weak var delegate: GameModeSelectionDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    func setupUI() {
        view.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        
        let mode1Button = UIButton(type: .system)
        mode1Button.setTitle("Single Player", for: .normal)
        mode1Button.addTarget(self, action: #selector(singlePlayerSelected), for: .touchUpInside)
        
        let mode2Button = UIButton(type: .system)
        mode2Button.setTitle("Multiplayer", for: .normal)
        mode2Button.addTarget(self, action: #selector(multiplayerSelected), for: .touchUpInside)
        
        let stackView = UIStackView(arrangedSubviews: [mode1Button, mode2Button])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 20
        
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    @objc func singlePlayerSelected() {
        delegate?.didSelectGameMode(isSinglePlayer: true)
        dismiss(animated: true, completion: nil)
    }
    
    @objc func multiplayerSelected() {
        delegate?.didSelectGameMode(isSinglePlayer: false)
        dismiss(animated: true, completion: nil)
    }
}

