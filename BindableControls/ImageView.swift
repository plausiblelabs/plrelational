//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class ImageView: NSImageView {

    public lazy var img: BindableProperty<Image> = WriteOnlyProperty { [unowned self] value, _ in
        self.image = value.nsimage
    }
    
    public override init(frame: NSRect) {
        super.init(frame: frame)
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
