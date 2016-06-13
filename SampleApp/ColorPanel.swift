//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

class ColorPanel {
    
    private let bindings = BindingSet()
    
    var color: MutableObservableValue<Color>? {
        didSet {
            bindings.observe(color, "color", { [weak self] value in
                self?.updateColorPanel(makeVisible: false)
            })
        }
    }
    
    // TODO: Need to watch color panel's window visibility and update this accordingly
    var visible: MutableObservableValue<Bool>? {
        didSet {
            // TODO: If shared color panel is already visible, commit(true) to keep the
            // binding value in sync
            bindings.observe(visible, "visible", { [weak self] value in
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
            // TODO: Use `transient: true` only while user is actively changing the color
            bindings.update(color, newValue: newColor, transient: true)
        }
    }
}