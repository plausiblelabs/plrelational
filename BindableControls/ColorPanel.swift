//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

open class ColorPanel {
    
    // XXX: Fix initial value
    fileprivate lazy var _color: MutableValueProperty<Color> = mutableValueProperty(Color.white, { [unowned self] newValue, _ in
        self.updateColorPanel(newColor: newValue, makeVisible: false)
    })
    open var color: ReadWriteProperty<Color> { return _color }

    // TODO: Need to watch color panel's window visibility and update this accordingly
    // TODO: Check whether shared color panel is already visible
    fileprivate lazy var _visible: MutableValueProperty<Bool> = mutableValueProperty(false, { [unowned self] newValue, _ in
        // TODO: Should we `orderOut` when visible goes to false?
        if newValue {
            self.updateColorPanel(newColor: self.color.value, makeVisible: true)
        }
    })
    open var visible: ReadWriteProperty<Bool> { return _visible }
    
    fileprivate var ignorePanelUpdates = false
    
    fileprivate func updateColorPanel(newColor: Color?, makeVisible: Bool) {
        ignorePanelUpdates = true
        
        let colorPanel = NSColorPanel.shared()
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorPanelChanged(_:)))
        if let nscolor = newColor?.nscolor {
            colorPanel.color = nscolor
        }
        if makeVisible {
            colorPanel.orderFront(nil)
        }
        
        ignorePanelUpdates = false
    }
    
    /// Called when the color panel color has changed.
    @objc func colorPanelChanged(_ panel: NSColorPanel) {
        if ignorePanelUpdates {
            return
        }
        
        if let newColor = Color(panel.color) {
            // TODO: Use `transient: true` only while user is actively changing the color
            _color.change(newColor, transient: true)
        }
    }
}
