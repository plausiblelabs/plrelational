//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import PLRelationalBinding

extension Bindable where Base: UISwitch {
    
    public var on: BindableProperty<Bool> {
        return WriteOnlyProperty(set: { [weak base = self.base] value, _ in
            base?.isOn = value
        })
    }
}
