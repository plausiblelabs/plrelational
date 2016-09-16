//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

open class TextField: NSTextField, NSTextFieldDelegate {

    private var timer: Timer?

    private lazy var changeHandler: ChangeHandler = ChangeHandler(
        onLock: { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.timer = Timer.scheduledTimer(timeInterval: 0.5, target: strongSelf, selector: #selector(timerFired), userInfo: nil, repeats: false)
        },
        onUnlock: { [weak self] in
            guard let strongSelf = self else { return }
            if let timer = strongSelf.timer {
                timer.invalidate()
                strongSelf.timer = nil
            } else {
                strongSelf.isEnabled = true
            }
        }
    )
    
    private lazy var _string: ExternalValueProperty<String> = ExternalValueProperty(
        get: { [unowned self] in
            self.stringValue
        },
        set: { [unowned self] value, _ in
            self.stringValue = value
        },
        changeHandler: self.changeHandler
    )
    open var string: ReadWriteProperty<String> { return _string }
    
    open lazy var placeholder: BindableProperty<String> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.placeholderString = value
    })

    open lazy var visible: BindableProperty<Bool> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.isHidden = !value
    })
    
    private var previousCommittedValue: String?
    private var previousValue: String?
    
    public override init(frame: NSRect) {
        super.init(frame: frame)
        
        self.delegate = self
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.delegate = self
    }
    
    open override func controlTextDidBeginEditing(_ obj: Notification) {
        //Swift.print("CONTROL DID BEGIN EDITING!")
        previousCommittedValue = stringValue
        previousValue = stringValue
    }
    
    open override func controlTextDidChange(_ notification: Notification) {
        //Swift.print("CONTROL DID CHANGE!")
        _string.changed(transient: true)
        previousValue = stringValue
    }
    
    open override func controlTextDidEndEditing(_ obj: Notification) {
        // Note that controlTextDidBeginEditing may not be called if the user gives focus to the text field
        // but resigns first responder without typing anything, so we only commit the value if the user
        // actually typed something that differs from the previous value
        //Swift.print("CONTROL DID END EDITING!")
        if let previousCommittedValue = previousCommittedValue {
            // TODO: Need to discard `before` snapshot if we're skipping the commit
            if stringValue != previousCommittedValue {
                _string.changed(transient: false)
            }
        }
        previousCommittedValue = nil
        previousValue = nil
    }
    
    @objc private func timerFired() {
        self.isEnabled = false
        timer?.invalidate()
        timer = nil
    }
}
