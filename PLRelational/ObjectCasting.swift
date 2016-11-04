//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


func asObject(_ value: Any) -> AnyObject? {
    if type(of: value) is AnyObject.Type {
        return value as AnyObject
    } else {
        return nil
    }
}
