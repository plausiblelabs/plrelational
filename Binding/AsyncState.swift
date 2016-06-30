//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public enum AsyncState<T> { case
    Computing(T?),
    Ready(T)
    
    public var data: T? {
        switch self {
        case .Computing(let existing):
            return existing
        case .Ready(let d):
            return d
        }
    }
    
    public var isComputing: Bool {
        switch self {
        case .Computing:
            return true
        case .Ready:
            return false
        }
    }
}
