//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public func debugLog(items: Any..., file: String = #file, line: Int = #line) {
    let strings = items.map({ String($0) })
    let fullString = strings.joinWithSeparator(" ")
    let filename = NSURL(fileURLWithPath: file).lastPathComponent ?? "<unknown>"
    NSLog("%@:%ld: %@", filename, line, fullString)
}

public func pointerString(obj: AnyObject) -> String {
    return String(format: "%p", unsafeBitCast(obj, Int.self))
}

public func pointerAndClassString(obj: AnyObject) -> String {
    return "<\(obj.dynamicType): \(pointerString(obj))>"
}
