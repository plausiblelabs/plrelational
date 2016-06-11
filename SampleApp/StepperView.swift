//
// Copyright (c) 2015 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

class StepperView: NSControl, NSTextFieldDelegate {
    
    private let bindings = BindingSet()
    
    var value: BidiValueBinding<Int?>? {
        didSet {
            bindings.register("value", value, { [weak self] value in
                guard let weakSelf = self else { return }
                if let intValue = value {
                    weakSelf.stepper.integerValue = intValue
                    weakSelf.textField.integerValue = intValue
                } else {
                    weakSelf.stepper.integerValue = weakSelf.defaultValue
                    weakSelf.textField.stringValue = ""
                }
            })
        }
    }

    var placeholder: ValueBinding<String>? {
        didSet {
            bindings.register("placeholder", placeholder, { [weak self] value in
                self?.textField.placeholderString = value
            })
        }
    }

    private let defaultValue: Int
    private var textField: NSTextField!
    private var stepper: NSStepper!

    init(frame: NSRect, min: Int, max: Int, defaultValue: Int) {
        self.defaultValue = defaultValue
        
        super.init(frame: frame)
        
        let formatter = NSNumberFormatter()
        formatter.minimum = min
        formatter.maximum = max
        formatter.generatesDecimalNumbers = false
        formatter.maximumFractionDigits = 0
        textField = NSTextField()
        textField.formatter = formatter
        textField.target = self
        textField.action = #selector(controlChanged(_:))
        textField.delegate = self
        addSubview(textField)
        
        stepper = NSStepper()
        stepper.valueWraps = false
        stepper.cell!.controlSize = .SmallControlSize
        stepper.target = self
        stepper.action = #selector(controlChanged(_:))
        stepper.minValue = Double(min)
        stepper.maxValue = Double(max)
        stepper.integerValue = defaultValue
        addSubview(stepper)
        
        setFrameSize(frame.size)
    }
    
    required init?(coder: NSCoder) {
        fatalError("NSCoding not supported")
    }
    
    override var flipped: Bool {
        return true
    }
    
    override func setFrameSize(newSize: NSSize) {
        super.setFrameSize(newSize)
        
        // XXX: NSStepper's width is zero until some later time, so for now just hardcode a width
        let stepperW: CGFloat = 12.0 // stepper.frame.width
        let stepperPad: CGFloat = 0.0
        
        var textFrame = textField.frame
        textFrame.origin.x = 0
        textFrame.origin.y = 0
        textFrame.size.width = newSize.width - stepperW - stepperPad
        textFrame.size.height = newSize.height
        textField.frame = textFrame
        
        var stepperFrame = stepper.frame
        stepperFrame.origin.x = newSize.width - stepperW
        stepperFrame.origin.y = 0
        stepperFrame.size.width = stepperW
        // XXX
        stepperFrame.size.height = newSize.height
        stepper.frame = stepperFrame
    }
    
    func controlChanged(sender: AnyObject) {
        let newValue: Int
        if let textField = sender as? NSTextField {
            newValue = textField.integerValue
            stepper.integerValue = newValue
        } else if let stepper = sender as? NSStepper {
            newValue = stepper.integerValue
            textField.integerValue = newValue
        } else {
            fatalError("Unexpected sender")
        }
        bindings.update(value, newValue: newValue)
    }
    
    override func controlTextDidEndEditing(notification: NSNotification) {
        let textField = notification.object! as! NSTextField
        if !textField.stringValue.isEmpty {
            controlChanged(textField)
        }
    }
}
