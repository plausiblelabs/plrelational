//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

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
    
    public var onCommand: ((Selector) -> Bool)?
    
    private lazy var _string: ExternalValueProperty<String> = ExternalValueProperty(
        get: { [unowned self] in
            self.stringValue
        },
        set: { [unowned self] value, _ in
            self.stringValue = value
        },
        changeHandler: self.changeHandler
    )
    public var string: ReadWriteProperty<String> { return _string }

    private lazy var _optString: ExternalValueProperty<String?> = ExternalValueProperty(
        get: { [unowned self] in
            self.stringValue
        },
        set: { [unowned self] value, _ in
            // This behavior is specific to optString: when `value` goes to nil, we keep the previous string value
            // in place.  This is mainly useful for the case where an outline view item is being deleted and the
            // relation associated with its TextField is becoming empty (thus resulting in a nil string value).
            // Without this special behavior, the cell text will flash to the placeholder string as it fades out.
            if let value = value {
                self.stringValue = value
            }
        },
        changeHandler: self.changeHandler
    )
    public var optString: ReadWriteProperty<String?> { return _optString }

    public lazy var placeholder: BindableProperty<String> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.placeholderString = value
    })

    public lazy var visible: BindableProperty<Bool> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.isHidden = !value
    })

    /// Whether to deliver transient changes.  If `true` a transient change will be delivered via the
    /// `string` property on each keystroke.  If `false` (the default), no transient changes will be
    /// delivered, and only a single commit change will be delivered when the user is done editing.
    public var deliverTransientChanges: Bool = false
    
    // XXX: For now we assume that either `string` or `optString` will be in use, but never both at the same time.
    private var usingOpt: Bool {
        return _optString.signal.observerCount > 0
    }
    
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
        _string.exclusiveMode = true
        _optString.exclusiveMode = true
        previousCommittedValue = stringValue
        previousValue = stringValue
    }
    
    open override func controlTextDidChange(_ notification: Notification) {
        //Swift.print("CONTROL DID CHANGE!")
        if deliverTransientChanges {
            if usingOpt {
                _optString.changed(transient: true)
            } else {
                _string.changed(transient: true)
            }
        }
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
                if usingOpt {
                    _optString.changed(transient: false)
                } else {
                    _string.changed(transient: false)
                }
            }
        }
        _string.exclusiveMode = false
        _optString.exclusiveMode = false
        previousCommittedValue = nil
        previousValue = nil
    }

    // TODO: TextField already serves as its own NSTextFieldDelegate, so if clients want to
    // add their own delegate, they'll be out of luck; for now we add optional callbacks for
    // certain things, but we should find a better approach.
    open func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        return onCommand?(commandSelector) ?? false
    }
    
    @objc private func timerFired() {
        self.isEnabled = false
        timer?.invalidate()
        timer = nil
    }
}
