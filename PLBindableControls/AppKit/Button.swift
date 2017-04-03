//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

open class Button: NSButton {

    public lazy var disabled: BindableProperty<Bool> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.isEnabled = !value
    })

    public let clicks: Signal<()>
    private let clicksNotify: Signal<()>.Notify
    
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