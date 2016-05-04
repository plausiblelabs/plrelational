//
// Copyright (c) 2015 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public class Box<T> {
    var value: T
    
    init(_ value: T) {
        self.value = value
    }
    
    static func open(obj: AnyObject?) -> T? {
        return (obj as? Box)?.value
    }
}

extension Box: CustomStringConvertible {
    public var description: String {
        return "Box<\(T.self)>(\(value))"
    }
}
