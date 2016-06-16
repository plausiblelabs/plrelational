//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class Button: NSButton {

    private let bindings = BindingSet()
    
    public var disabled: ObservableValue<Bool>? {
        didSet {
            bindings.observe(disabled, "disabled", { [weak self] value in
                self?.enabled = !value
            })
        }
    }

    public var clicked: MutableObservableValue<Bool>? {
        didSet {
            bindings.observe(clicked, "clicked", { _ in })
        }
    }

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
    
    @objc func buttonClicked(sender: Button) {
        guard let clicked = clicked else { return }

        let metadata = ChangeMetadata(transient: true)
        clicked.update(true, metadata)
        clicked.update(false, metadata)
    }
}
