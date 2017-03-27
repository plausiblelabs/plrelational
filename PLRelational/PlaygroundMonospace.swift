//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif

public protocol PlaygroundMonospace: CustomStringConvertible, CustomPlaygroundQuickLookable {}

extension PlaygroundMonospace {
    public var customPlaygroundQuickLook: PlaygroundQuickLook {
#if os(macOS)
        let attrstr = NSAttributedString(string: self.description,
                                         attributes: [NSFontAttributeName: NSFont(name: "Monaco", size: 9)!])
#else
        let attrstr = NSAttributedString(string: self.description)
#endif
        return PlaygroundQuickLook(reflecting: attrstr)
    }
}
