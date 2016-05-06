
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
    public static func EQ(lhs: ValueProvider, _ rhs: ValueProvider) -> ComparisonTerm {
        return self.init(lhs, EqualityComparator(), rhs)
    }
}

extension ComparisonTerm {
    public static func terms(terms: [ComparisonTerm], matchRow row: Row) -> Bool {
        return !terms.contains({ term in
            let lhs = term.lhs.valueForRow(row)
            let rhs = term.rhs.valueForRow(row)
            return !term.op.matches(lhs, rhs)
        })
    }
    
    /// Return a set of ComparisonTerms that correspond to the given row. Each value
    /// in the row will generate an EqualityComparator matching that attribute and
    /// that value.
    public static func termsFromRow(row: Row) -> [ComparisonTerm] {
        return row.values.map({ $0 *== $1 })
    }
}

infix operator *== {}

public func *==(lhs: ValueProvider, rhs: ValueProvider) -> ComparisonTerm {
    return ComparisonTerm(lhs, EqualityComparator(), rhs)
}
