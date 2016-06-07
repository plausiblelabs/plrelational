infix operator ∩ {
    associativity left
    precedence 140
}

/// Union two possibly-nil relations together. The result is nil if both inputs are nil.
/// We use + instead of ∪ because it's easier to type and can still be understood.
public func +(lhs: Relation?, rhs: Relation?) -> Relation? {
    switch (lhs, rhs) {
    case let (.Some(lhs), .Some(rhs)):
        return lhs.union(rhs)
    case let (.Some(lhs), .None):
        return lhs
    case let (.None, .Some(rhs)):
        return rhs
    case (.None, .None):
        return nil
    }
}

/// Subtract two possibly-nil relations. The result is nil if the lhs is nil, the lhs
/// is returned if the rhs is nil, and the difference is returned if both exist.
public func -(lhs: Relation?, rhs: Relation?) -> Relation? {
    if let lhs = lhs, rhs = rhs {
        return lhs.difference(rhs)
    } else if let lhs = lhs {
        return lhs
    } else {
        return nil
    }
}

/// Intersect two possibly-nil relations. The result is nil if either operand is nil.
/// I couldn't come up with a nice ASCII version of this operator, so we get the real
/// untypeable thing. Use copy/paste or the character viewer.
public func ∩(lhs: Relation?, rhs: Relation?) -> Relation? {
    if let lhs = lhs, rhs = rhs {
        return lhs.intersection(rhs)
    } else {
        return nil
    }
}