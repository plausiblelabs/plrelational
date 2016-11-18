//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


/// Collapse a double optional into a single optional, transforming .some(nil) into nil.
func flatten<T>(_ doubleOptional: T??) -> T? {
    switch doubleOptional {
    case .none, .some(.none): return nil
    case .some(.some(let wrapped)): return wrapped
    }
}
