//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public enum AsyncState<T> { case
    computing(T?),
    ready(T)
    
    public var data: T? {
        switch self {
        case .computing(let existing):
            return existing
        case .ready(let d):
            return d
        }
    }
    
    public var isComputing: Bool {
        switch self {
        case .computing:
            return true
        case .ready:
            return false
        }
    }
}
