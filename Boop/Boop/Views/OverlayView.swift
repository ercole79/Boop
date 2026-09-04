//
//  OverlayView.swift
//  Boop
//
//  Created by Ivan on 1/27/19.
//  Copyright © 2019 OKatBest. All rights reserved.
//

import Cocoa

class OverlayView: NSView {

    var onMouseDown: (() -> Void)?

    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        self.wantsLayer = true
        self.clipsToBounds = true
        // Set hidden directly — animator() during init can leave the view
        // visible to hit-testing while alpha is 0, blocking editor input.
        self.isHidden = true
        self.alphaValue = 0
        
        setBackground()
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else {
            return nil
        }
        return super.hitTest(point)
    }
    
    func setBackground() {
        
        self.layer?.backgroundColor = ColorPair.overlayColor.value(for: self.effectiveAppearance).cgColor
        
        
    }
    
    
    func show() {
        
        self.animator().alphaValue = 1
        self.animator().isHidden = false
    }
    
    func hide() {
        
        self.animator().alphaValue = 0
        self.animator().isHidden = true
    }
    
    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.setBackground()
    }
    
}
