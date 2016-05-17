
public protocol SelectExpression {
    func valueWithRow(row: Row) -> RelationValue
}

extension RelationValue: SelectExpression {
    public func valueWithRow(row: Row) -> RelationValue {
        return self
    }
}

extension Attribute: SelectExpression {
    public func valueWithRow(row: Row) -> RelationValue {
        return row[self]
    }
}

extension String: SelectExpression {
    public func valueWithRow(row: Row) -> RelationValue {
        return RelationValue(self)
    }
}

extension Int: SelectExpression {
    public func valueWithRow(row: Row) -> RelationValue {
        return RelationValue(Int64(self))
    }
}

extension Bool: SelectExpression {
    public func valueWithRow(row: Row) -> RelationValue {
        return RelationValue.boolValue(true)
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
    
    public func valueWithRow(row: Row) -> RelationValue {
        let lvalue = lhs.valueWithRow(row)
        let rvalue = rhs.valueWithRow(row)
        return op.evaluate(lvalue, rvalue)
    }
}

public struct SelectExpressionUnaryOperator: SelectExpression {
    public var op: UnaryOperator
    public var expr: SelectExpression
    
    public init(op: UnaryOperator, expr: SelectExpression) {
        self.op = op
        self.expr = expr
    }
    
    public func valueWithRow(row: Row) -> RelationValue {
        return op.evaluate(expr.valueWithRow(row))
    }
}

/// Return a SelectExpression that corresponds to the given row. Each value
/// in the row will generate an EqualityComparator matching that attribute and
/// that value, and the whole mess will be ANDed together.
func SelectExpressionFromRow(row: Row) -> SelectExpression {
    let equalityExpressions = row.values.map({ $0 *== $1 })
    if equalityExpressions.isEmpty {
        return RelationValue.Integer(1)
    } else if equalityExpressions.count == 1 {
        return equalityExpressions.first!
    } else {
        var expressionSoFar = equalityExpressions[0] *&& equalityExpressions[1]
        for expr in equalityExpressions.dropFirst(2) {
            expressionSoFar = expressionSoFar *&& expr
        }
        return expressionSoFar
    }
}

extension SelectExpression {
    /// Walk the entire expression tree, calling a map function at each node.
    /// Child nodes are mapped first, and then the map function is called on
    /// the parent node after the new values are substituted in.
    func mapTree(f: SelectExpression -> SelectExpression) -> SelectExpression{
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
}

extension SelectExpression {
    func withRenamedAttributes(renames: [Attribute: Attribute]) -> SelectExpression {
        return self.mapTree({
            switch $0 {
            case let attribute as Attribute:
                return renames[attribute] ?? attribute
            default:
                return $0
            }
        })
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
