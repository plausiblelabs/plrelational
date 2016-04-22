
public struct ComparisonTerm {
    var lhs: ValueProvider
    var op: Comparator
    var rhs: ValueProvider
    
    public init(_ lhs: ValueProvider, _ op: Comparator, _ rhs: ValueProvider) {
        self.lhs = lhs
        self.op = op
        self.rhs = rhs
    }
}

extension ComparisonTerm {
    static func EQ(lhs: ValueProvider, _ rhs: ValueProvider) -> ComparisonTerm {
        return self.init(lhs, EqualityComparator(), rhs)
    }
}
