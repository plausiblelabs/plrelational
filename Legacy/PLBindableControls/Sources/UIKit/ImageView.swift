//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import PLRelationalBinding

extension Bindable where Base: UIImageView {
    
    public var image: BindableProperty<Image> {
        return WriteOnlyProperty(set: { [weak base = self.base] value, _ in
            base?.image = value.uiimage
        })
    }
}
