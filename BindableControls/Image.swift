//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa

/// This serves as an insulation layer to avoid having platform-specific (i.e., Cocoa)
/// dependencies in the model, which should be platform-independent.  Currently it only
/// supports loading a named image from the application's resource bundle.
public class Image {
    internal let nsimage: NSImage?

    public init(_ nsimage: NSImage) {
        self.nsimage = nsimage
    }

    public init(named name: String) {
        self.nsimage = NSImage(named: name)
    }
}
