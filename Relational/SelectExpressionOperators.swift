//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Swift
infix operator *==: ComparisonPrecedence

public func *==(lhs: SelectExpression, rhs: SelectExpression) -> SelectExpression {
    return SelectExpressionBinaryOperator(lhs: lhs, op: EqualityComparator(), rhs: rhs)
}

infix operator *&&: LogicalConjunctionPrecedence

infix operator *||: LogicalDisjunctionPrecedence

public func *&&(lhs: SelectExpression, rhs: SelectExpression) -> SelectExpression {
    return SelectExpressionBinaryOperator(lhs: lhs, op: AndComparator(), rhs: rhs)
}

public func *||(lhs: SelectExpression, rhs: SelectExpression) -> SelectExpression {
    return SelectExpressionBinaryOperator(lhs: lhs, op: OrComparator(), rhs: rhs)
}

prefix operator *!

public prefix func *!(expr: SelectExpression) -> SelectExpression {
    return SelectExpressionUnaryOperator(op: NotOperator(), expr: expr)
}
