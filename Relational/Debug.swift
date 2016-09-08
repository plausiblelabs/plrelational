//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public func debugLog(_ items: Any..., file: String = #file, line: Int = #line) {
    let strings = items.map({ String(describing: $0) })
    let fullString = strings.joined(separator: " ")
    let filename = URL(fileURLWithPath: file).lastPathComponent ?? "<unknown>"
    NSLog("%@:%ld: %@", filename, line, fullString)
}

public func pointerString(_ obj: AnyObject) -> String {
    return String(format: "%p", unsafeBitCast(obj, to: Int.self))
}

public func pointerAndClassString(_ obj: AnyObject) -> String {
    return "<\(type(of: obj)): \(pointerString(obj))>"
}
