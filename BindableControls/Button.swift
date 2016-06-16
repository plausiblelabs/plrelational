//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class Button: NSButton {

    private let bindings = BindingSet()
    
    public lazy var disabled: Property<Bool> = Property { [weak self] value in
        self?.enabled = !value
    }

    // TODO: Make this an event stream, and then bind the view model to the stream
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
