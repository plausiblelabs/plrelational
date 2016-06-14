//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class ImageView: NSImageView {

    private let bindings = BindingSet()
    
    public var img: ObservableValue<Image>? {
        didSet {
            bindings.observe(img, "img", { [weak self] value in
                self?.image = value.nsimage
            })
        }
    }
    
    public override init(frame: NSRect) {
        super.init(frame: frame)
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
