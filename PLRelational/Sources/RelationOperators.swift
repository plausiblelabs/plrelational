//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

infix operator ∩ : AdditionPrecedence

/// Union two possibly-nil relations together. The result is nil if both inputs are nil.
/// We use + instead of ∪ because it's easier to type and can still be understood.
public func +(lhs: Relation?, rhs: Relation?) -> Relation? {
    switch (lhs, rhs) {
    case let (.some(lhs), .some(rhs)):
        return lhs.union(rhs)
    case let (.some(lhs), .none):
        return lhs
    case let (.none, .some(rhs)):
        return rhs
    case (.none, .none):
        return nil
    }
}

/// Subtract two possibly-nil relations. The result is nil if the lhs is nil, the lhs
/// is returned if the rhs is nil, and the difference is returned if both exist.
public func -(lhs: Relation?, rhs: Relation?) -> Relation? {
    if let lhs = lhs, let rhs = rhs {
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
    if let lhs = lhs, let rhs = rhs {
        return lhs.intersection(rhs)
    } else {
        return nil
    }
}
