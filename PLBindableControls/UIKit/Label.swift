//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import PLRelationalBinding

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
