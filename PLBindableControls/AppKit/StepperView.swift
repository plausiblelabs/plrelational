//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

open class StepperView: NSControl, NSTextFieldDelegate {
    
    private lazy var _value: MutableValueProperty<Int?> = mutableValueProperty(nil, { [unowned self] value, _ in
        if let intValue = value {
            self.stepper.integerValue = intValue
            self.textField.integerValue = intValue
        } else {
            self.stepper.integerValue = self.defaultValue
            self.textField.stringValue = ""
        }
    })
    public var value: ReadWriteProperty<Int?> { return _value }

    public lazy var placeholder: BindableProperty<String> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.textField.placeholderString = value
    })

    private let defaultValue: Int
    private var textField: NSTextField!
    private var stepper: NSStepper!

    public init(frame: NSRect, min: Int, max: Int, defaultValue: Int) {
        self.defaultValue = defaultValue
        
        super.init(frame: frame)
        
        let formatter = NumberFormatter()
        formatter.minimum = min as NSNumber?
        formatter.maximum = max as NSNumber?
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
        stepper.cell!.controlSize = .small
        stepper.target = self
        stepper.action = #selector(controlChanged(_:))
        stepper.minValue = Double(min)
        stepper.maxValue = Double(max)
        stepper.integerValue = defaultValue
        addSubview(stepper)
        
        setFrameSize(frame.size)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("NSCoding not supported")
    }
    
    open override var isFlipped: Bool {
        return true
    }
    
    open override func setFrameSize(_ newSize: NSSize) {
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
    
    @objc func controlChanged(_ sender: AnyObject) {
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
        _value.change(newValue, transient: false)
    }
    
    open override func controlTextDidEndEditing(_ notification: Notification) {
        let textField = notification.object! as! NSTextField
        if !textField.stringValue.isEmpty {
            controlChanged(textField)
        }
    }
}
