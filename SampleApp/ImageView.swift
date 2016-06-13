//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

class ImageView: NSImageView {

    private let bindings = BindingSet()
    
    var img: ObservableValue<Image>? {
        didSet {
            bindings.observe(img, "img", { [weak self] value in
                self?.image = value.nsimage
            })
        }
    }
    
    override init(frame: NSRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
