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

    var img: ValueBinding<Image>? {
        didSet {
            imgBindingRemoval?()
            imgBindingRemoval = nil
            if let img = img {
                image = img.value.nsimage
                imgBindingRemoval = img.addChangeObserver({ [weak self] in
                    guard let weakSelf = self else { return }
                    weakSelf.image = img.value.nsimage
                })
            } else {
                image = nil
            }
        }
    }
    
    private var imgBindingRemoval: ObserverRemoval?
    
    override init(frame: NSRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    deinit {
        imgBindingRemoval?()
    }
}
