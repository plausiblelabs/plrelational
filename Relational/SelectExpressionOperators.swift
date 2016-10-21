//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Swift

infix operator *==: ComparisonPrecedence
infix operator *<: ComparisonPrecedence
infix operator *<=: ComparisonPrecedence
infix operator *>: ComparisonPrecedence
infix operator *>=: ComparisonPrecedence

public func *==(lhs: SelectExpression, rhs: SelectExpression) -> SelectExpression {
    return SelectExpressionBinaryOperator(lhs: lhs, op: EqualityComparator(), rhs: rhs)
}

public func *<(lhs: SelectExpression, rhs: SelectExpression) -> SelectExpression {
    return SelectExpressionBinaryOperator(lhs: lhs, op: LTComparator(), rhs: rhs)
}

public func *<=(lhs: SelectExpression, rhs: SelectExpression) -> SelectExpression {
    return SelectExpressionBinaryOperator(lhs: lhs, op: LEComparator(), rhs: rhs)
}

public func *>(lhs: SelectExpression, rhs: SelectExpression) -> SelectExpression {
    return SelectExpressionBinaryOperator(lhs: lhs, op: GTComparator(), rhs: rhs)
}

public func *>=(lhs: SelectExpression, rhs: SelectExpression) -> SelectExpression {
    return SelectExpressionBinaryOperator(lhs: lhs, op: GEComparator(), rhs: rhs)
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
