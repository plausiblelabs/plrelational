//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa

public struct Color: Hashable {
    
    public struct Components: Hashable {
        public let r: CGFloat
        public let g: CGFloat
        public let b: CGFloat
        public let a: CGFloat
        
        public init() {
            self.init(r: 0, g: 0, b: 0, a: 0)
        }
        
        public init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
            self.r = r
            self.g = g
            self.b = b
            self.a = a
        }
        
        public var hashValue: Int {
            return r.hashValue ^ g.hashValue ^ b.hashValue ^ a.hashValue
        }
    }
    
    public let components: Components
    
    public init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1.0) {
        self.components = Components(r: r, g: g, b: b, a: a)
    }
    
    public init(white: CGFloat, a: CGFloat = 1.0) {
        self.components = Components(r: white, g: white, b: white, a: a)
    }
    
    public init?(string: String) {
        let stringComps = string.componentsSeparatedByString(" ")
        if stringComps.count != 4 {
            return nil
        }
        let comps = stringComps.map{ s -> CGFloat in
            if let f = NSNumberFormatter().numberFromString(s) {
                let floatVal = CGFloat(f)
                if floatVal < 0.0 {
                    return 0.0
                } else if floatVal > 1.0 {
                    return 1.0
                } else {
                    return floatVal
                }
            } else {
                return 1.0
            }
        }
        self.init(r: comps[0], g: comps[1], b: comps[2], a: comps[3])
    }
    
    public func withAlpha(newAlpha: CGFloat) -> Color {
        return Color(r: components.r, g: components.g, b: components.b, a: newAlpha)
    }
    
    public var hashValue: Int {
        return components.hashValue
    }
    
    public var stringValue: String {
        return [components.r, components.g, components.b, components.a].map{ String($0) }.joinWithSeparator(" ")
    }
}

extension Color.Components {
    init?(_ nscolor: NSColor) {
        guard let converted = nscolor.colorUsingColorSpace(NSColorSpace.genericRGBColorSpace()) else { return nil }
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 0.0
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r: r, g: g, b: b, a: a)
    }
    
    public var nscolor: NSColor {
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }
}

public func ==(a: Color.Components, b: Color.Components) -> Bool {
    return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a
}

public func ==(a: Color, b: Color) -> Bool {
    return a.components == b.components
}

extension Color {
    public init?(_ nscolor: NSColor) {
        guard let components = Components(nscolor) else { return nil }
        self.components = components
    }
    
    public var nscolor: NSColor {
        return components.nscolor
    }
    
    public static let black = Color(r: 0, g: 0, b: 0)
    public static let white = Color(r: 1, g: 1, b: 1)
    public static let clear = Color(r: 0, g: 0, b: 0)
    
    public static let red    = Color(NSColor.redColor())!
    public static let orange = Color(NSColor.orangeColor())!
    public static let yellow = Color(NSColor.yellowColor())!
    public static let green  = Color(NSColor.greenColor())!
    public static let blue   = Color(NSColor.blueColor())!
    public static let purple = Color(NSColor.purpleColor())!
}
