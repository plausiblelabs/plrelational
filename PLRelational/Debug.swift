//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


/// :nodoc:
public func debugLog(_ items: Any..., file: String = #file, line: Int = #line) {
    let strings = items.map({ String(describing: $0) })
    let fullString = strings.joined(separator: " ")
    let filename = URL(fileURLWithPath: file).lastPathComponent 
    NSLog("%@:%ld: %@", filename, line, fullString)
}

/// :nodoc:
public func pointerString(_ obj: AnyObject) -> String {
    return String(format: "%p", unsafeBitCast(obj, to: Int.self))
}

/// :nodoc:
public func pointerAndClassString(_ obj: AnyObject) -> String {
    return "<\(type(of: obj)): \(pointerString(obj))>"
}
