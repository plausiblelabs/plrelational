//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// This serves as an insulation layer to avoid having platform-specific (i.e., AppKit or UIKit)
/// dependencies in the model, which should be platform-independent.
public class Image {

#if os(macOS)
    public let nsimage: NSImage

    public init(_ nsimage: NSImage) {
        self.nsimage = nsimage
    }

    public init?(named name: String) {
        guard let nsimage = NSImage(named: name) else { return nil }
        self.nsimage = nsimage
    }
#else
    public let uiimage: UIImage
    
    public init(_ uiimage: UIImage) {
        self.uiimage = uiimage
    }
    
    public init?(named name: String) {
        guard let uiimage = UIImage(named: name) else { return nil }
        self.uiimage = uiimage
    }
#endif
}
