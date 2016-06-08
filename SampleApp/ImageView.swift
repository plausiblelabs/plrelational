//
//  ImageView.swift
//  Relational
//
//  Created by Chris Campbell on 6/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import Binding

class ImageView: NSImageView {

    private let bindings = BindingSet()
    
    var img: ValueBinding<Image>? {
        didSet {
            bindings.register("img", img, { [weak self] value in
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
