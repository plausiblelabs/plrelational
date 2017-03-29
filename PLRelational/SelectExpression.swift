//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public protocol SelectExpression {
    func valueWithRow(_ row: Row) -> RelationValue
}

extension Attribute: SelectExpression {
    public func valueWithRow(_ row: Row) -> RelationValue {
        return row[self]
    }
}

public protocol SelectExpressionConstantValue: SelectExpression {
    var relationValue: RelationValue { get }
}

extension RelationValue: SelectExpressionConstantValue {
    public var relationValue: RelationValue {
        return self
    }
}

extension SelectExpressionConstantValue {
    public func valueWithRow(_ row: Row) -> RelationValue {
        return self.relationValue
    }
}

extension String: SelectExpressionConstantValue {
    public var relationValue: RelationValue {
        return RelationValue(self)
    }
}

extension Int: SelectExpressionConstantValue {
    public var relationValue: RelationValue  {
        return RelationValue(Int64(self))
    }
}

extension Int64: SelectExpressionConstantValue {
    public var relationValue: RelationValue {
        return RelationValue(self)
    }
}

extension Bool: SelectExpressionConstantValue {
    public var relationValue: RelationValue {
        return RelationValue.boolValue(self)
    }
}

public struct SelectExpressionBinaryOperator: SelectExpression {
    public var lhs: SelectExpression
    public var op: BinaryOperator
    public var rhs: SelectExpression
    
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

public struct SelectExpressionUnaryOperator: SelectExpression {
    public var op: UnaryOperator
    public var expr: SelectExpression
    
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

extension SelectExpressionBinaryOperator: CustomStringConvertible {
    public var description: String {
        return "(\(lhs)) \(op) (\(rhs))"
    }
}

extension SelectExpressionUnaryOperator: CustomStringConvertible {
    public var description: String {
        return "\(op)(\(expr))"
    }
}
