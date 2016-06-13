//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

class ValueWithDestructor<T> {
    var value: T
    let destructor: T -> Void
    
    init(value: T, destructor: T -> Void) {
        self.value = value
        self.destructor = destructor
    }
    
    deinit {
        destructor(value)
    }
}
