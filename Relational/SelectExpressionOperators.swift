//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

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

infix operator *|| {
    associativity left
    precedence 110
}

public func *&&(lhs: SelectExpression, rhs: SelectExpression) -> SelectExpression {
    return SelectExpressionBinaryOperator(lhs: lhs, op: AndComparator(), rhs: rhs)
}

public func *||(lhs: SelectExpression, rhs: SelectExpression) -> SelectExpression {
    return SelectExpressionBinaryOperator(lhs: lhs, op: OrComparator(), rhs: rhs)
}

prefix operator *! {}

public prefix func *!(expr: SelectExpression) -> SelectExpression {
    return SelectExpressionUnaryOperator(op: NotOperator(), expr: expr)
}
