//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

open class Checkbox: NSButton {
    
    private var timer: Timer?
    
    // TODO: Re-enable timer hack once we fix it to account for `disabled` property
//    private lazy var changeHandler: ChangeHandler = ChangeHandler(
//        onLock: { [weak self] in
//            guard let strongSelf = self else { return }
//            strongSelf.timer = Timer.scheduledTimer(timeInterval: 0.5, target: strongSelf, selector: #selector(timerFired), userInfo: nil, repeats: false)
//        },
//        onUnlock: { [weak self] in
//            guard let strongSelf = self else { return }
//            if let timer = strongSelf.timer {
//                timer.invalidate()
//                strongSelf.timer = nil
//            } else {
//                strongSelf.isEnabled = true
//            }
//        }
//    )

    private lazy var _checkState: ExternalValueProperty<CheckState> = ExternalValueProperty(
        get: { [unowned self] in
            return CheckState(self.state)
        },
        set: { [unowned self] value, _ in
            // Only allow mixed state if we are starting in a mixed state; otherwise we
            // use simple two-state mode
            self.allowsMixedState = value == .mixed
            self.state = value.nsValue
        }
//        changeHandler: self.changeHandler
    )
    public var checkState: ReadWriteProperty<CheckState> { return _checkState }
    
    public lazy var disabled: BindableProperty<Bool> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.isEnabled = !value
    })
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.switch)
        target = self
        action = #selector(checkboxToggled(_:))
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setButtonType(.switch)
        target = self
        action = #selector(checkboxToggled(_:))
    }
    
    @objc func checkboxToggled(_ sender: Checkbox) {
        // Note that by the time this function is called, `state` already reflects the new value.
        // Cocoa always wants to cycle through the states (including mixed), but we only want the user
        // to be able to choose on/off, so disable allowsMixedState here.
        allowsMixedState = false
        _checkState.changed(transient: false)
    }
    
    open override func accessibilityValue() -> Any? {
        return CheckState(state).rawValue
    }
    
    @objc private func timerFired() {
        self.isEnabled = false
        timer?.invalidate()
        timer = nil
    }
}
