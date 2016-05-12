infix operator *== {
    associativity none
    precedence 130
}

public func *==(lhs: SelectExpression, rhs: SelectExpression) -> SelectExpression {
    return SelectExpressionBinaryOperator(lhs: lhs, op: EqualityComparator(), rhs: rhs)
}

infix operator *&& {
    associativity left
    precedence 120
}

public func *&&(lhs: SelectExpression, rhs: SelectExpression) -> SelectExpression {
    return SelectExpressionBinaryOperator(lhs: lhs, op: AndComparator(), rhs: rhs)
}

prefix operator *! {}

public prefix func *!(expr: SelectExpression) -> SelectExpression {
    return SelectExpressionUnaryOperator(op: NotOperator(), expr: expr)
}
