//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa

struct Color: Hashable {
    
    struct Components: Hashable {
        var r: CGFloat
        var g: CGFloat
        var b: CGFloat
        var a: CGFloat
        
        init() {
            self.init(r: 0, g: 0, b: 0, a: 0)
        }
        
        init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
            self.r = r
            self.g = g
            self.b = b
            self.a = a
        }
        
        var hashValue: Int {
            return r.hashValue ^ g.hashValue ^ b.hashValue ^ a.hashValue
        }
    }
    
    let components: Components
    
    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1.0) {
        self.components = Components(r: r, g: g, b: b, a: a)
    }
    
    init(white: CGFloat, a: CGFloat = 1.0) {
        self.components = Components(r: white, g: white, b: white, a: a)
    }
    
    init?(string: String) {
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
    
    func withAlpha(newAlpha: CGFloat) -> Color {
        return Color(r: components.r, g: components.g, b: components.b, a: newAlpha)
    }
    
    var hashValue: Int {
        return components.hashValue
    }
    
    var stringValue: String {
        return [components.r, components.g, components.b, components.a].map{ String($0) }.joinWithSeparator(" ")
    }
}

extension Color.Components {
    init?(_ nscolor: NSColor) {
        self.init()
        guard let converted = nscolor.colorUsingColorSpace(NSColorSpace.genericRGBColorSpace()) else { return nil }
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
    }
    
    var nscolor: NSColor {
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }
}

func ==(a: Color.Components, b: Color.Components) -> Bool {
    return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a
}

func ==(a: Color, b: Color) -> Bool {
    return a.components == b.components
}

extension Color {
    init?(_ nscolor: NSColor) {
        guard let components = Components(nscolor) else { return nil }
        self.components = components
    }
    
    var nscolor: NSColor {
        return components.nscolor
    }
    
    static let black = Color(r: 0, g: 0, b: 0)
    static let white = Color(r: 1, g: 1, b: 1)
    static let clear = Color(r: 0, g: 0, b: 0)
    
    static let red    = Color(NSColor.redColor())!
    static let orange = Color(NSColor.orangeColor())!
    static let yellow = Color(NSColor.yellowColor())!
    static let green  = Color(NSColor.greenColor())!
    static let blue   = Color(NSColor.blueColor())!
    static let purple = Color(NSColor.purpleColor())!
}
