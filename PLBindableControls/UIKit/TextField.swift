//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import PLRelationalBinding

open class TextField: UITextField, UITextFieldDelegate {
    
    private lazy var _bindable_text: ExternalValueProperty<String> = ExternalValueProperty(
        get: {
            self.text ?? ""
        },
        set: { value, _ in
            self.text = value
        }
    )
    public var bindable_text: ReadWriteProperty<String> { return _bindable_text }
    
    /// Whether to deliver transient changes.  If `true` a transient change will be delivered via the
    /// `string` property on each keystroke.  If `false` (the default), no transient changes will be
    /// delivered, and only a single commit change will be delivered when the user is done editing.
    // TODO: For now we assume deliverTransientChanges==true
//    public var deliverTransientChanges: Bool = false
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.delegate = self
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.delegate = self
    }

    open func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        _bindable_text.changed(transient: true)
        return true
    }
}
