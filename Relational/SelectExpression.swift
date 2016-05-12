
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

public struct SelectExpressionBinaryOperator: SelectExpression {
    public var lhs: SelectExpression
    public var op: Comparator
    public var rhs: SelectExpression
    
    public init(lhs: SelectExpression, op: Comparator, rhs: SelectExpression) {
        self.lhs = lhs
        self.op = op
        self.rhs = rhs
    }
    
    public func valueWithRow(row: Row) -> RelationValue {
        let lvalue = lhs.valueWithRow(row)
        let rvalue = rhs.valueWithRow(row)
        let result = op.matches(lvalue, rvalue)
        return .Integer(result ? 1 : 0)
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
        return op.transform(expr.valueWithRow(row))
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
    func withRenamedAttributes(renames: [Attribute: Attribute]) -> SelectExpression {
        switch self {
        case let attribute as Attribute:
            return renames[attribute] ?? attribute
        case let binary as SelectExpressionBinaryOperator:
            return SelectExpressionBinaryOperator(
                lhs: binary.lhs.withRenamedAttributes(renames),
                op: binary.op,
                rhs: binary.rhs.withRenamedAttributes(renames))
        case let unary as SelectExpressionUnaryOperator:
            return SelectExpressionUnaryOperator(
                op: unary.op,
                expr: unary.expr.withRenamedAttributes(renames))
        default:
            return self
        }
    }
}
