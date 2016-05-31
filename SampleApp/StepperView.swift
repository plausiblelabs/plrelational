//
// Copyright (c) 2015 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

class StepperView: NSControl, NSTextFieldDelegate {
    
    var value: BidiValueBinding<Int?>? {
        didSet {
            valueBindingRemoval?()
            valueBindingRemoval = nil
            if let binding = value {
                func updateControls(view: StepperView) {
                    if let intValue = binding.value {
                        view.stepper.integerValue = intValue
                        view.textField.integerValue = intValue
                    } else {
                        view.stepper.integerValue = view.defaultValue
                        view.textField.stringValue = ""
                    }
                }
                updateControls(self)
                valueBindingRemoval = binding.addChangeObserver({ [weak self] in
                    guard let weakSelf = self else { return }
                    updateControls(weakSelf)
                })
            } else {
                stepper.integerValue = defaultValue
                textField.stringValue = ""
            }
        }
    }

    var placeholder: ValueBinding<String>? {
        didSet {
            placeholderBindingRemoval?()
            placeholderBindingRemoval = nil
            if let placeholder = placeholder {
                textField.placeholderString = placeholder.value
                placeholderBindingRemoval = placeholder.addChangeObserver({ [weak self] in
                    guard let weakSelf = self else { return }
                    weakSelf.textField.placeholderString = placeholder.value
                })
            } else {
                textField.placeholderString = ""
            }
        }
    }

    private let defaultValue: Int
    private var textField: NSTextField!
    private var stepper: NSStepper!

    private var valueBindingRemoval: ObserverRemoval?
    private var placeholderBindingRemoval: ObserverRemoval?

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
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.target = self
        textField.action = #selector(controlChanged(_:))
        textField.delegate = self
        addSubview(textField)
        
        stepper = NSStepper()
        stepper.valueWraps = false
        stepper.cell!.controlSize = .SmallControlSize
        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.target = self
        stepper.action = #selector(controlChanged(_:))
        stepper.minValue = Double(min)
        stepper.maxValue = Double(max)
        stepper.integerValue = defaultValue
        addSubview(stepper)
    }
    
    required init?(coder: NSCoder) {
        fatalError("NSCoding not supported")
    }
    
    override var flipped: Bool {
        return true
    }
    
    override func setFrameSize(newSize: NSSize) {
        super.setFrameSize(newSize)
        
        let stepperW = stepper.frame.width
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
        stepper.frame = stepperFrame
    }
    
    func controlChanged(sender: AnyObject) {
        let newValue: Int
        if let textField = sender as? NSTextField {
            newValue = textField.integerValue
        } else if let stepper = sender as? NSStepper {
            newValue = stepper.integerValue
        } else {
            return
        }
        value?.commit(newValue)
    }
    
    override func controlTextDidEndEditing(notification: NSNotification) {
        let textField = notification.object! as! NSTextField
        if !textField.stringValue.isEmpty {
            controlChanged(textField)
        }
    }
}
