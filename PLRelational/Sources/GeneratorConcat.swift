//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc: Implementation detail (will be made non-public eventually)
extension IteratorProtocol {
    public func concat<OtherGen: IteratorProtocol>(_ other: OtherGen) -> ConcatGenerator<Self, OtherGen> {
        return ConcatGenerator(self, other)
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
/// A GeneratorType which concatenates two other generators. It will produce all elements from
/// the first generator, then all elements from the second.
public struct ConcatGenerator<G1: IteratorProtocol, G2: IteratorProtocol>: IteratorProtocol where G1.Element == G2.Element {
    var g1: G1?
    var g2: G2?
    
    public init(_ g1: G1, _ g2: G2) {
        self.g1 = g1
        self.g2 = g2
    }
    
    public mutating func next() -> G1.Element? {
        if g1 != nil {
            if let element = g1?.next() {
                return element
            } else {
                g1 = nil
            }
        }
        // NOTE: not else if, because we want to fall through after the g1 = nil above.
        if g2 != nil {
            if let element = g2?.next() {
                return element
            } else {
                g2 = nil
            }
        }
        
        return nil
    }
}
