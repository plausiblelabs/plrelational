
extension GeneratorType {
    public func concat<OtherGen: GeneratorType where OtherGen.Element == Self.Element>(other: OtherGen) -> ConcatGenerator<Self, OtherGen> {
        return ConcatGenerator(self, other)
    }
}

/// A GeneratorType which concatenates two other generators. It will produce all elements from
/// the first generator, then all elements from the second.
public struct ConcatGenerator<G1: GeneratorType, G2: GeneratorType where G1.Element == G2.Element>: GeneratorType {
    var g1: G1
    var g2: G2
    var current: Int
    
    public init(_ g1: G1, _ g2: G2) {
        self.g1 = g1
        self.g2 = g2
        self.current = 0
    }
    
    public mutating func next() -> G1.Element? {
        if current == 0 {
            if let element = g1.next() {
                return element
            } else {
                current = 1
            }
        }
        // NOTE: not else if, because we want to fall through when current == 0 assigns current = 1 above.
        if current == 1 {
            if let element = g2.next() {
                return element
            } else {
                current = 2
            }
        }
        
        return nil
    }
}
