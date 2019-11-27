//
// Copyright (c) 2015 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

class Box<T> {
    let value: T
    
    init(_ value: T) {
        self.value = value
    }
    
    static func open(_ obj: AnyObject?) -> T? {
        return (obj as? Box)?.value
    }
}

extension Box: CustomStringConvertible {
    var description: String {
        return "Box<\(T.self)>(\(value))"
    }
}
