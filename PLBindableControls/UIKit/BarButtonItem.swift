//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import PLRelationalBinding

// TODO: Convert this to Bindable extension
public class BarButtonItem: UIBarButtonItem {
    
    public lazy var bindable_enabled: BindableProperty<Bool> = {
        return WriteOnlyProperty(set: { [weak self] value, _ in
            self?.isEnabled = value
        })
    }()
    
    public let bindable_clicks: Signal<()>
    private let clicksNotify: Signal<()>.Notify

    public override init() {
        (bindable_clicks, clicksNotify) = Signal.pipe()
        super.init()
        target = self
        action = #selector(buttonClicked(_:))
    }

    public required init?(coder: NSCoder) {
        (bindable_clicks, clicksNotify) = Signal.pipe()
        super.init(coder: coder)
        target = self
        action = #selector(buttonClicked(_:))
    }

    @objc func buttonClicked(_ sender: BarButtonItem) {
        clicksNotify.valueChanging((), ChangeMetadata(transient: true))
    }
}
