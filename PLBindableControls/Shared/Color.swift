//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif

import PLRelational

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
            return DJBHash.hash(values: [r.hashValue, g.hashValue, b.hashValue, a.hashValue])
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
        let stringComps = string.components(separatedBy: " ")
        if stringComps.count != 4 {
            return nil
        }
        let comps = stringComps.map{ s -> CGFloat in
            if let f = NumberFormatter().number(from: s) {
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
    
    public func withAlpha(_ newAlpha: CGFloat) -> Color {
        return Color(r: components.r, g: components.g, b: components.b, a: newAlpha)
    }
    
    public var hashValue: Int {
        return components.hashValue
    }
    
    public var stringValue: String {
        return [components.r, components.g, components.b, components.a].map{ String(describing: $0) }.joined(separator: " ")
    }
}

#if os(macOS)
extension Color.Components {
    init?(_ nscolor: NSColor) {
        guard let converted = nscolor.usingColorSpace(NSColorSpace.genericRGB) else { return nil }
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
#else
extension Color.Components {
    init?(_ uicolor: UIColor) {
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 0.0
        if !uicolor.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return nil
        }
        self.init(r: r, g: g, b: b, a: a)
    }
    
    public var uicolor: UIColor {
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}
#endif

public func ==(a: Color.Components, b: Color.Components) -> Bool {
    return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a
}

public func ==(a: Color, b: Color) -> Bool {
    return a.components == b.components
}

extension Color {
#if os(macOS)
    public init?(_ nscolor: NSColor) {
        guard let components = Components(nscolor) else { return nil }
        self.components = components
    }
    
    public var nscolor: NSColor {
        return components.nscolor
    }
    
    public var native: NSColor {
        return nscolor
    }
#else
    public init?(_ uicolor: UIColor) {
        guard let components = Components(uicolor) else { return nil }
        self.components = components
    }
    
    public var uicolor: UIColor {
        return components.uicolor
    }
    
    public var native: UIColor {
        return uicolor
    }
#endif

    public static let black = Color(r: 0, g: 0, b: 0)
    public static let white = Color(r: 1, g: 1, b: 1)
    public static let clear = Color(r: 0, g: 0, b: 0)

#if os(macOS)
    public static let red    = Color(NSColor.red)!
    public static let orange = Color(NSColor.orange)!
    public static let yellow = Color(NSColor.yellow)!
    public static let green  = Color(NSColor.green)!
    public static let blue   = Color(NSColor.blue)!
    public static let purple = Color(NSColor.purple)!
#else
    public static let red    = Color(UIColor.red)!
    public static let orange = Color(UIColor.orange)!
    public static let yellow = Color(UIColor.yellow)!
    public static let green  = Color(UIColor.green)!
    public static let blue   = Color(UIColor.blue)!
    public static let purple = Color(UIColor.purple)!
#endif
}
