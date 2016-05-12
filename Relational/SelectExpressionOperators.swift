infix operator *== {}

public func *==(lhs: SelectExpression, rhs: SelectExpression) -> SelectExpression {
    return SelectExpressionBinaryOperator(lhs: lhs, op: EqualityComparator(), rhs: rhs)
}

infix operator *&& {}

public func *&&(lhs: SelectExpression, rhs: SelectExpression) -> SelectExpression {
    return SelectExpressionBinaryOperator(lhs: lhs, op: AndComparator(), rhs: rhs)
}
