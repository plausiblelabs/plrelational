//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import PLRelationalBinding

public enum LabelText {
    case readOnly(ReadableProperty<String>)
    case asyncReadOnly(AsyncReadableProperty<String>)
    case readOnlyOpt(ReadableProperty<String?>)
    case asyncReadOnlyOpt(AsyncReadableProperty<String?>)
}

extension UILabel {
    public func bind(_ text: LabelText?) {
        // TODO: Hmm, with this `bindable` extension approach, there's no way to explicitly unbind existing bindings
        // since each access of `bindable.text` returns a fresh property instance
        if let text = text {
            switch text {
            case .readOnly(let prop):
                bindable.text <~ prop
            case .asyncReadOnly(let prop):
                bindable.text <~ prop
            case .readOnlyOpt(let prop):
                bindable.optText <~ prop
            case .asyncReadOnlyOpt(let prop):
                bindable.optText <~ prop
            }
        }
    }
}

extension Bindable where Base: UILabel {
    
    public var text: BindableProperty<String> {
        return WriteOnlyProperty(set: { [weak base = self.base] value, _ in
            base?.text = value
        })
    }

    public var optText: BindableProperty<String?> {
        // This behavior is specific to optText: when `value` goes to nil, we keep the previous string value
        // in place.  This is mainly useful for the case where an table view cell is being deleted and the
        // relation associated with its Label is becoming empty (thus resulting in a nil string value).
        // Without this special behavior, the cell text will flash to the placeholder string as it fades out.
        return WriteOnlyProperty(set: { [weak base = self.base] value, _ in
            if let value = value {
                base?.text = value
            }
        })
    }
}
