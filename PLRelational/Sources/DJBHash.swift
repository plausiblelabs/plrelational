//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc: Implementation detail (will be made non-public eventually)
/// An implementation of the DJB hash function, adapted from http://stackoverflow.com/questions/31438210/how-to-implement-the-hashable-protocol-in-swift-for-an-int-array-a-custom-strin
public struct DJBHash {
    public private(set) var value: Int = 5381
    
    public mutating func combine(_ new: Int) {
        value = (value << 5) &+ value &+ new
    }
    
    public init() {}
    
    public static func hash<S: Sequence>(values: S) -> Int where S.Iterator.Element == Int {
        var hash = DJBHash()
        for value in values {
            hash.combine(value)
        }
        return hash.value
    }
}
