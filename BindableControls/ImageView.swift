//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

open class ImageView: NSImageView {

    open lazy var img: BindableProperty<Image> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.image = value.nsimage
    })
    
    public override init(frame: NSRect) {
        super.init(frame: frame)
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
