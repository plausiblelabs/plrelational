//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


/// :nodoc:
/// Collapse a double optional into a single optional, transforming .some(nil) into nil.
public func flatten<T>(_ doubleOptional: T??) -> T? {
    switch doubleOptional {
    case .none, .some(.none): return nil
    case .some(.some(let wrapped)): return wrapped
    }
}

/// :nodoc:
/// Collapse two optionals into an optional tuple with non-optional components.
/// If either parameter is nil, the return value is nil.
public func flatten<T, U>(_ t: T?, _ u: U?) -> (T, U)? {
    if let t = t, let u = u {
        return (t, u)
    } else {
        return nil
    }
}
