//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class ColorPanel {
    
    // XXX: Fix initial value
    private lazy var _color: ValueBidiProperty<Color> = ValueBidiProperty(Color.blue, { [unowned self] newValue, _ in
        self.updateColorPanel(newColor: newValue, makeVisible: false)
    })
    public var color: BidiProperty<Color> { return _color }

    // TODO: Need to watch color panel's window visibility and update this accordingly
    // TODO: Check whether shared color panel is already visible
    private lazy var _visible: ValueBidiProperty<Bool> = ValueBidiProperty(false, { [unowned self] newValue, _ in
        // TODO: Should we `orderOut` when visible goes to false?
        if newValue {
            self.updateColorPanel(newColor: self.color.get(), makeVisible: true)
        }
    })
    public var visible: BidiProperty<Bool> { return _visible }
    
    private var ignorePanelUpdates = false
    
    private func updateColorPanel(newColor newColor: Color?, makeVisible: Bool) {
        ignorePanelUpdates = true
        
        let colorPanel = NSColorPanel.sharedColorPanel()
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
    @objc func colorPanelChanged(panel: NSColorPanel) {
        if ignorePanelUpdates {
            return
        }
        
        if let newColor = Color(panel.color) {
            // TODO: Use `transient: true` only while user is actively changing the color
            _color.change(newValue: newColor, transient: true)
        }
    }
}
