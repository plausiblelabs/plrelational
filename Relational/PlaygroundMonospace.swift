//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa

public protocol PlaygroundMonospace: CustomStringConvertible, CustomPlaygroundQuickLookable {}

extension PlaygroundMonospace {
    public func customPlaygroundQuickLook() -> PlaygroundQuickLook {
        let attrstr = NSAttributedString(string: self.description,
                                         attributes: [NSFontAttributeName: NSFont(name: "Monaco", size: 9)!])
        return PlaygroundQuickLook(reflecting: attrstr)
    }
}
