//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


/// A really simple generic class that boxes a mutable value.
/// The intent is to allow for in-place mutations of value-typed collections in situations
/// where Swift isn't smart enough to figure out how otherwise.
class MutableBox<T> {
    var value: T
    
    init(_ initialValue: T) {
        value = initialValue
    }
}
