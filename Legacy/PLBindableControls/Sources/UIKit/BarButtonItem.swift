//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import PLRelationalBinding

// TODO: Convert this to Bindable extension
open class BarButtonItem: UIBarButtonItem {
    
    public lazy var bindable_enabled: BindableProperty<Bool> = {
        return WriteOnlyProperty(set: { [weak self] value, _ in
            self?.isEnabled = value
        })
    }()

    private let _bindable_clicks = SourceSignal<()>()
    public var bindable_clicks: Signal<()> { return _bindable_clicks }

    public override init() {
        super.init()
        target = self
        action = #selector(buttonClicked(_:))
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        target = self
        action = #selector(buttonClicked(_:))
    }

    @objc func buttonClicked(_ sender: BarButtonItem) {
        _bindable_clicks.notifyAction()
    }
}
