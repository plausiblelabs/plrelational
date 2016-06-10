//
//  ColorPanel.swift
//  Relational
//
//  Created by Chris Campbell on 6/10/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import Binding

class ColorPanel {
    
    private let bindings = BindingSet()
    
    var color: BidiValueBinding<Color>? {
        didSet {
            bindings.register("color", color, { [weak self] value in
                self?.updateColorPanel(makeVisible: false)
            })
        }
    }
    
    // TODO: Need to watch color panel's window visibility and update this accordingly
    var visible: BidiValueBinding<Bool>? {
        didSet {
            bindings.register("visible", visible, { [weak self] value in
                // TODO: Should we `orderOut` when visible goes to false?
                if value {
                    self?.updateColorPanel(makeVisible: true)
                }
            })
        }
    }
    
    private var ignorePanelUpdates = false
    
    private func updateColorPanel(makeVisible makeVisible: Bool) {
        ignorePanelUpdates = true
        
        let colorPanel = NSColorPanel.sharedColorPanel()
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorPanelChanged(_:)))
        if let nscolor = color?.value.nscolor {
            colorPanel.color = nscolor
        }
        if makeVisible {
            colorPanel.orderFront(nil)
        }
        
        ignorePanelUpdates = false
    }
    
    /// Called when the color panel color has changed.
    @objc func colorPanelChanged(panel: NSColorPanel) {
        if ignorePanelUpdates {
            return
        }
        
        if let newColor = Color(panel.color) {
            // TODO: Use `update` while value is changing, and `commit` when done
            color?.update(newColor)
        }
    }
}
