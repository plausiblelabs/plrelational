//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

extension SelectExpression {
    /// Perform some basic simplifications of the expression. This short-circuits logical operators
    /// with a constant on one side and immediately evaluates operators with constant operands.
    func shallowSimplify() -> SelectExpression {
        switch self {
        case let op as SelectExpressionUnaryOperator:
            if let expr = op.expr as? Bool {
                return !expr
            }
            return self
            
        case let op as SelectExpressionBinaryOperator:
            switch (op.op, op.lhs, op.rhs) {
            case let (op, lhs as SelectExpressionConstantValue, rhs as SelectExpressionConstantValue):
                return op.evaluate(lhs.relationValue, rhs.relationValue)
                
            case let (_ as AndComparator, true, rhs):
                return rhs
            case (_ as AndComparator, false, _):
                return false
            case let (_ as AndComparator, lhs, true):
                return lhs
            case (_ as AndComparator, _, false):
                return false
                
            case let (_ as OrComparator, false, rhs):
                return rhs
            case (_ as OrComparator, true, _):
                return true
            case let (_ as OrComparator, lhs, false):
                return lhs
            case (_ as OrComparator, _, true):
                return true
                
            default:
                return self
            }
            
        default:
            return self
        }
    }
    
    /// Walk the entire expression, calling shallowSimplify as we go to simplify as much as possible.
    func deepSimplify() -> SelectExpression {
        return mapTree({ $0.shallowSimplify() })
    }
}
