//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// A protocol which represents a select expression. A select expression
/// can be applied to a `Row` to produce a value. This is typically used
/// to filter `Relation`s using expressions which return booleans.
public protocol SelectExpression {
    /// Evaluate the expression for the given `Row` and return the resulting value.
    func valueWithRow(_ row: Row) -> RelationValue
}

extension Attribute: SelectExpression {
    public func valueWithRow(_ row: Row) -> RelationValue {
        return row[self]
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
/// A protocol for select expressions which are always constant values.
/// In other words, the return value from `valueWithRow` does not depend
/// the `Row` passed in.
public protocol SelectExpressionConstantValue: SelectExpression {
    /// The actual value this expression contains. This value must match
    /// the value returned by `valueWithRow`. The protocol provides a
    /// default implementation for `valueWithRow` which returns this.
    var relationValue: RelationValue { get }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension RelationValue: SelectExpressionConstantValue {
    public var relationValue: RelationValue {
        return self
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension SelectExpressionConstantValue {
    public func valueWithRow(_ row: Row) -> RelationValue {
        return self.relationValue
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension String: SelectExpressionConstantValue {
    public var relationValue: RelationValue {
        return RelationValue(self)
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension Int: SelectExpressionConstantValue {
    public var relationValue: RelationValue  {
        return RelationValue(Int64(self))
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension Int64: SelectExpressionConstantValue {
    public var relationValue: RelationValue {
        return RelationValue(self)
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension Bool: SelectExpressionConstantValue {
    public var relationValue: RelationValue {
        return RelationValue.boolValue(self)
    }
}

extension SelectExpression {
    /// If the SelectExpression is a SelectExpressionConstantValue, returns its boolean value.
    /// Otherwise returns nil.
    public var constantBoolValue: Bool? {
        return (self as? SelectExpressionConstantValue)?.relationValue.boolValue
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
/// A select expression consisting of a binary operator applied to two sub-expressions.
public struct SelectExpressionBinaryOperator: SelectExpression {
    /// The left-hand side.
    public var lhs: SelectExpression
    
    /// The operator.
    public var op: BinaryOperator
    
    /// The right-hand side.
    public var rhs: SelectExpression
    
    /// Create a new binary operator expression.
    public init(lhs: SelectExpression, op: BinaryOperator, rhs: SelectExpression) {
        self.lhs = lhs
        self.op = op
        self.rhs = rhs
    }
    
    public func valueWithRow(_ row: Row) -> RelationValue {
        let lvalue = lhs.valueWithRow(row)
        let rvalue = rhs.valueWithRow(row)
        return op.evaluate(lvalue, rvalue)
    }
}

public extension SelectExpression {
    /// If the expression is a SelectExpressionBinaryOperator and the operator is an
    /// instance of the given type, then return the two operands. Otherwise return nil.
    func binaryOperands<T: BinaryOperator>(_ op: T.Type) -> (SelectExpression, SelectExpression)? {
        if let cast = self as? SelectExpressionBinaryOperator, cast.op is T {
            return (cast.lhs, cast.rhs)
        } else {
            return nil
        }
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
/// A select expression consisting of a unary operator applied to a sub-expression.
public struct SelectExpressionUnaryOperator: SelectExpression {
    /// The operator.
    public var op: UnaryOperator
    
    /// The sub-expression.
    public var expr: SelectExpression
    
    /// Create a new unary operator expression.
    public init(op: UnaryOperator, expr: SelectExpression) {
        self.op = op
        self.expr = expr
    }
    
    public func valueWithRow(_ row: Row) -> RelationValue {
        return op.evaluate(expr.valueWithRow(row))
    }
}

/// Return a SelectExpression that corresponds to the given row. Each value
/// in the row will generate an EqualityComparator matching that attribute and
/// that value, and the whole mess will be ANDed together.
func SelectExpressionFromRow(_ row: Row) -> SelectExpression {
    let equalityExpressions = row.map({ $0 *== $1 })
    return equalityExpressions.combined(with: *&&) ?? RelationValue.integer(1)
}

extension SelectExpression {
    /// Walk the entire expression tree, calling a map function at each node.
    /// Child nodes are mapped first, and then the map function is called on
    /// the parent node after the new values are substituted in.
    func mapTree(_ f: (SelectExpression) -> SelectExpression) -> SelectExpression {
        switch self {
        case let binary as SelectExpressionBinaryOperator:
            let substituted = SelectExpressionBinaryOperator(
                lhs: binary.lhs.mapTree(f),
                op: binary.op,
                rhs: binary.rhs.mapTree(f))
            return f(substituted)
        case let unary as SelectExpressionUnaryOperator:
            let substituted = SelectExpressionUnaryOperator(
                op: unary.op,
                expr: unary.expr.mapTree(f))
            return f(substituted)
        default:
            return f(self)
        }
    }
    
    /// Walk the entire expression tree, calling a function at each node.
    func iterateTree(_ f: (SelectExpression) -> Void) {
        f(self)
        
        switch self {
        case let binary as SelectExpressionBinaryOperator:
            binary.lhs.iterateTree(f)
            binary.rhs.iterateTree(f)
        case let unary as SelectExpressionUnaryOperator:
            unary.expr.iterateTree(f)
        default:
            break
        }
    }
}

extension SelectExpression {
    /// Rename all of the `Attribute`s in the expresson according to the key/value pairs in `renames`.
    func withRenamedAttributes(_ renames: [Attribute: Attribute]) -> SelectExpression {
        return self.mapTree({
            switch $0 {
            case let attribute as Attribute:
                return renames[attribute] ?? attribute
            default:
                return $0
            }
        })
    }
    
    /// Get all attributes in the expression.
    func allAttributes() -> Set<Attribute> {
        var result: Set<Attribute> = []
        self.iterateTree({
            if let attribute = $0 as? Attribute {
                result.insert(attribute)
            }
        })
        return result
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension Sequence where Iterator.Element == SelectExpression {
    /// Combine a sequence of SelectExpressions using the given combining function. The combination
    /// is performed in a way that attempts to produce the shallowest possible tree in the result.
    /// This is a convenient way to AND or OR a bunch of expressions together.
    public func combined(with combine: (SelectExpression, SelectExpression) -> SelectExpression) -> SelectExpression? {
        // Build up a tree of elements that combine the subexpressions. We do this in a weird pairwise way
        // to keep the tree shallow.
        var expressions = Array(self)
        while expressions.count > 1 {
            for i in 0 ..< expressions.count / 2 {
                let lhs = expressions.remove(at: i)
                let rhs = expressions.remove(at: i)
                expressions.insert(combine(lhs, rhs), at: i)
            }
        }
        return expressions.first
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension SelectExpressionBinaryOperator: CustomStringConvertible {
    public var description: String {
        return "(\(lhs)) \(op) (\(rhs))"
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension SelectExpressionUnaryOperator: CustomStringConvertible {
    public var description: String {
        return "\(op)(\(expr))"
    }
}
