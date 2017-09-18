//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// :nodoc: Implementation detail (will be made non-public eventually)
public protocol PlaygroundMonospace: CustomStringConvertible, CustomPlaygroundQuickLookable {}

/// :nodoc: Implementation detail (will be made non-public eventually)
extension PlaygroundMonospace {
    public var customPlaygroundQuickLook: PlaygroundQuickLook {
#if os(macOS)
        let attrstr = NSAttributedString(string: self.description,
                                         attributes: [NSAttributedStringKey.font: NSFont(name: "Monaco", size: 9)!])
#else
        let attrstr = NSAttributedString(string: self.description)
#endif
        return PlaygroundQuickLook(reflecting: attrstr)
    }
}
