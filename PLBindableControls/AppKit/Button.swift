//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

open class Button: NSButton {

    public private(set) lazy var visible: BindableProperty<Bool> = WriteOnlyProperty(set: { [weak self] value, _ in
        self?.isHidden = !value
    })

    public private(set) lazy var disabled: BindableProperty<Bool> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.isEnabled = !value
    })

    public private(set) lazy var string: BindableProperty<String> = WriteOnlyProperty(set: { [weak self] value, _ in
        self?.title = value
    })

    private let _clicks = SourceSignal<()>()
    public var clicks: Signal<()> { return _clicks }
    
    public override init(frame: NSRect) {
        super.init(frame: frame)
        target = self
        action = #selector(buttonClicked(_:))
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        target = self
        action = #selector(buttonClicked(_:))
    }
    
    @objc func buttonClicked(_ sender: Button) {
        _clicks.notifyAction()
    }
}
