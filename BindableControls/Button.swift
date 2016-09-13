//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

open class Button: NSButton {

    open lazy var disabled: BindableProperty<Bool> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.isEnabled = !value
    })

    open let clicks: Signal<()>
    fileprivate let clicksNotify: Signal<()>.Notify
    
    public override init(frame: NSRect) {
        (clicks, clicksNotify) = Signal.pipe()
        super.init(frame: frame)
        target = self
        action = #selector(buttonClicked(_:))
    }
    
    public required init?(coder: NSCoder) {
        (clicks, clicksNotify) = Signal.pipe()
        super.init(coder: coder)
        target = self
        action = #selector(buttonClicked(_:))
    }
    
    @objc func buttonClicked(_ sender: Button) {
        clicksNotify.valueChanging((), ChangeMetadata(transient: true))
    }
}
