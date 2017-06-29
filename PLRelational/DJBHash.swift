//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// An implementation of the DJB hash function, adapted from http://stackoverflow.com/questions/31438210/how-to-implement-the-hashable-protocol-in-swift-for-an-int-array-a-custom-strin
public struct DJBHash {
    public private(set) var value: Int = 5381
    
    public mutating func combine(_ new: Int) {
        value = (value << 5) &+ value &+ new
    }
    
    public init() {}
}
