//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

open class TextView: NSTextView, NSTextViewDelegate {

    private lazy var _text: ExternalValueProperty<String> = ExternalValueProperty(
        get: { [unowned self] in
            self.string
        },
        set: { [unowned self] value, _ in
            self.string = value
            // XXX: Without the following sometimes part of the text will disappear, not sure why yet
            self.layoutManager?.invalidateLayout(forCharacterRange: NSMakeRange(0, value.characters.count), actualCharacterRange: nil)
        }
    )
    public var text: ReadWriteProperty<String> { return _text }
    
    private var previousString: String?
    
    public override init(frame: NSRect) {
        super.init(frame: frame)
        configure()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }
    
    private func configure() {
        // XXX: Keep built-in undo support disabled until we decide how to make it play
        // nicely with our own undo stuff
        self.allowsUndo = false
        self.delegate = self
    }

    open func textDidBeginEditing(_ notification: Notification) {
        previousString = self.string
    }

    open func textDidEndEditing(_ notification: Notification) {
        if let previousString = previousString {
            if self.string != previousString {
                _text.changed(transient: false)
            }
        }
        previousString = nil
    }
}
