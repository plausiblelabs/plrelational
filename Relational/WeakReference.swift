//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

struct WeakReference<T: AnyObject> {
    weak var value: T?
}
