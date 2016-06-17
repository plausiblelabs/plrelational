//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class Button: NSButton {

    public lazy var disabled: Property<Bool> = Property { [weak self] value, _ in
        self?.enabled = !value
    }

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
    
    @objc func buttonClicked(sender: Button) {
        clicksNotify(newValue: (), metadata: ChangeMetadata(transient: true))
    }
}
