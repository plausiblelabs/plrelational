//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import AppKit

extension NSColor {
    /// Initialize a color with 255-based component values.
    convenience init(r: Int, g: Int, b: Int, a: Int = 255) {
        func convert(_ component: Int) -> CGFloat {
            return CGFloat(component) / 255.0
        }
        self.init(calibratedRed: convert(r), green: convert(g), blue: convert(b), alpha: convert(a))
    }
}
