//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// A generalized Relation which derives its value by performing some operation on other Relations.
/// This implements operations such as union, intersection, difference, join, etc.
public class IntermediateRelation: Relation, RelationDefaultChangeObserverImplementation {
    var op: Operator
    var operands: [Relation] {
        didSet {
            let objs = operands.flatMap({ $0 as? AnyObject })
            if objs.contains({ $0 === self }) {
                fatalError()
            }
        }
    }
    
    public var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    var derivative: RelationDerivative?
    var inTransaction = 0 // Like a refcount, incremented for begin, decremented for end, action at 0
    
    var didRegisterObservers = false
    
    public init(op: Operator, operands: [Relation]) {
        self.op = op
        self.operands = operands
        
        switch op {
        case .Difference:
            precondition(operands.count == 2)
        case .Project:
            precondition(operands.count == 1)
        case .Select:
            precondition(operands.count == 1)
        case .Equijoin:
            precondition(operands.count == 2)
        case .Rename(let renames):
            precondition(operands.count == 1)
            precondition(self.scheme.attributes.count == operands[0].scheme.attributes.count, "Renaming \(operands[0].scheme) with renames \(renames) produced a collision")
        case .Update:
            precondition(operands.count == 1)
        case .Aggregate:
            precondition(operands.count == 1)
        default:
            precondition(operands.count > 0 && operands.count <= 2)
        }
        LogRelationCreation(self)
    }
}

extension IntermediateRelation {
    public enum Operator {
        case Union
        case Intersection
        case Difference
        
        case Project(Scheme)
        case Select(SelectExpression)
        case MutableSelect(SelectExpression)
        case Equijoin([Attribute: Attribute])
        case Rename([Attribute: Attribute])
        case Update(Row)
        case Aggregate(Attribute, RelationValue?, (RelationValue?, RelationValue) -> Result<RelationValue, RelationError>)
        
        case Otherwise
        case Unique(Attribute, RelationValue)
    }
}

extension IntermediateRelation {
    static func union(operands: [Relation]) -> Relation {
        if operands.count == 1 {
            return operands[0]
        } else {
            return IntermediateRelation(op: .Union, operands: operands)
        }
    }
    
    static func intersection(operands: [Relation]) -> Relation {
        if operands.count == 1 {
            return operands[0]
        } else {
            return IntermediateRelation(op: .Intersection, operands: operands)
        }
    }
    
    /// A convenience initializer for aggregating functions which cannot fail and which always
    /// compare two values. If the initial value is nil, then the aggregate of an empty relation
    /// is empty, the aggregate of a relation containing a single row is the value stored in
    /// that row. The aggregate function is only called if there are two or more rows, and the
    /// first two call will pass in the values of the first two rows.
    static func aggregate(relation: Relation, attribute: Attribute, initial: RelationValue?, agg: (RelationValue, RelationValue) -> RelationValue) -> Relation {
        return IntermediateRelation(op: .Aggregate(attribute, initial, { (a, b) -> Result<RelationValue, RelationError> in
            if let a = a {
                return .Ok(agg(a, b))
            } else {
                return .Ok(b)
            }
        }), operands: [relation])
    }
}

extension IntermediateRelation: RelationObserver {
    public func onAddFirstObserver() {
        let differentiator = RelationDifferentiator(relation: self)
        let derivative = differentiator.computeDerivative()
        self.derivative = derivative
        
        if !didRegisterObservers {
            for variable in derivative.allVariables where variable !== self {
                let proxy = WeakRelationObserverProxy(target: self)
                proxy.registerOn(variable, kinds: [.DirectChange])
            }
            didRegisterObservers = true
        }
    }
    
    public func onRemoveLastObserver() {
        self.derivative = nil
    }
    
    public func transactionBegan() {
        inTransaction += 1
        derivative?.clearVariables()
    }
    
    public func relationChanged(relation: Relation, change: RelationChange) {
        if let derivative = derivative {
            if inTransaction == 0 {
                derivative.clearVariables()
                derivative.setChange(change, forVariable: relation as! protocol<AnyObject, Relation>)
                notifyChangeObservers(derivative.change, kind: .DependentChange)
            } else {
                derivative.setChange(change, forVariable: relation as! protocol<AnyObject, Relation>)
            }
        }
    }
    
    public func transactionEnded() {
        inTransaction -= 1
        if let derivative = derivative where inTransaction == 0 {
            notifyChangeObservers(derivative.change, kind: .DependentChange)
        }
    }
}

extension IntermediateRelation {
    func otherOperands(excludingIndex: Int) -> [Relation] {
        var result = operands
        result.removeAtIndex(excludingIndex)
        return result
    }
}

extension IntermediateRelation {
    public var scheme: Scheme {
        switch op {
        case .Project(let scheme):
            return scheme
        case .Equijoin:
            let myAttributes = operands.reduce(Set(), combine: { $0.union($1.scheme.attributes) })
            return Scheme(attributes: myAttributes)
        case .Rename(let renames):
            let newAttributes = Set(operands[0].scheme.attributes.map({ renames[$0] ?? $0 }))
            return Scheme(attributes: newAttributes)
        case .Aggregate(let attribute, _, _):
            return [attribute]
        default:
            return operands[0].scheme
        }
    }
}

extension IntermediateRelation {
    private func isUnique(attribute: Attribute, _ matching: RelationValue) -> Result<Bool, RelationError> {
        var valueSoFar: RelationValue?
        for rowResult in self.operands[0].rows() {
            switch rowResult {
            case .Ok(let row):
                let value = row[attribute]
                if valueSoFar == nil {
                    valueSoFar = value
                } else if valueSoFar != value {
                    return .Ok(false)
                }
            case .Err(let err):
                return .Err(err)
            }
        }
        return .Ok(valueSoFar != nil)
    }
}

extension IntermediateRelation {
    public func contains(row: Row) -> Result<Bool, RelationError> {
        switch op {
        case .Union:
            return unionContains(row)
        case .Intersection:
            return intersectionContains(row)
        case .Difference:
            return differenceContains(row)
        case .Project:
            return projectContains(row)
        case .Select(let expression):
            return selectContains(row, expression: expression)
        case .MutableSelect(let expression):
            return selectContains(row, expression: expression)
        case .Equijoin:
            return equijoinContains(row)
        case .Rename(let renames):
            return renameContains(row, renames: renames)
        case .Update(let newValues):
            return updateContains(row, newValues: newValues)
        case .Aggregate:
            return aggregateContains(row)
        case .Otherwise:
            return otherwiseContains(row)
        case .Unique(let attribute, let value):
            return uniqueContains(row, attribute: attribute, value: value)
        }
    }
    
    func unionContains(row: Row) -> Result<Bool, RelationError> {
        for r in operands {
            switch r.contains(row) {
            case .Ok(let contains):
                if contains {
                    return .Ok(true)
                }
            case .Err(let err):
                return .Err(err)
            }
        }
        return .Ok(false)
    }
    
    func intersectionContains(row: Row) -> Result<Bool, RelationError> {
        for r in operands {
            switch r.contains(row) {
            case .Ok(let contains):
                if !contains {
                    return .Ok(false)
                }
            case .Err(let err):
                return .Err(err)
            }
        }
        return .Ok(operands.count > 0)
    }
    
    func differenceContains(row: Row) -> Result<Bool, RelationError> {
        return operands[0].contains(row).combine(operands[1].contains(row)).map({ $0 && !$1 })
    }
    
    func projectContains(row: Row) -> Result<Bool, RelationError> {
        return operands[0].select(row).isEmpty.map(!)
    }
    
    func selectContains(row: Row, expression: SelectExpression) -> Result<Bool, RelationError> {
        if !expression.valueWithRow(row).boolValue {
            return .Ok(false)
        } else {
            return operands[0].contains(row)
        }
    }
    
    func equijoinContains(row: Row) -> Result<Bool, RelationError> {
        return select(row).isEmpty.map(!)
    }
    
    func renameContains(row: Row, renames: [Attribute: Attribute]) -> Result<Bool, RelationError> {
        let renamedRow = row.renameAttributes(renames.reversed)
        return operands[0].contains(renamedRow)
    }
    
    func updateContains(row: Row, newValues: Row) -> Result<Bool, RelationError> {
        let newValuesScheme = Set(newValues.values.keys)
        let newValueParts = row.rowWithAttributes(newValuesScheme)
        if newValueParts != newValues {
            return .Ok(false)
        }
        
        let untouchedAttributes = Set(operands[0].scheme.attributes.subtract(newValues.values.keys))
        let projected = operands[0].project(Scheme(attributes: untouchedAttributes))
        
        let remainingParts = row.rowWithAttributes(projected.scheme.attributes)
        return projected.contains(remainingParts)
    }
    
    func aggregateContains(row: Row) -> Result<Bool, RelationError> {
        return containsOk(rows(), { $0 == row })
    }
    
    func otherwiseContains(row: Row) -> Result<Bool, RelationError> {
        for operand in operands {
            switch operand.contains(row) {
            case .Ok(let contains):
                if contains {
                    return .Ok(true)
                }
            case .Err(let err):
                return .Err(err)
            }
            
            switch operand.isEmpty {
            case .Ok(let empty):
                if !empty {
                    return .Ok(false)
                }
            case .Err(let err):
                return .Err(err)
            }
        }
        return .Ok(false)
    }
    
    func uniqueContains(row: Row, attribute: Attribute, value: RelationValue) -> Result<Bool, RelationError> {
        return isUnique(attribute, value).then({
            if $0 {
                return operands[0].contains(row)
            } else {
                return .Ok(false)
            }
        })
    }
}

extension IntermediateRelation {
    public func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        switch op {
        case .Union:
            return updateOperandsDirectly(query, newValues: newValues)
        case .Intersection:
            return intersectionUpdate(query, newValues: newValues)
        case .Difference:
            return differenceUpdate(query, newValues: newValues)
        case .Project:
            return updateOperandsDirectly(query, newValues: newValues)
        case .Select(let expression):
            return selectUpdate(query, newValues: newValues, expression: expression)
        case .MutableSelect(let expression):
            return selectUpdate(query, newValues: newValues, expression: expression)
        case .Equijoin:
            return equijoinUpdate(query, newValues: newValues)
        case .Rename(let renames):
            return renameUpdate(query, newValues: newValues, renames: renames)
        case .Update(let myNewValues):
            return updateUpdate(query, newValues: newValues, myNewValues: myNewValues)
        case .Aggregate:
            return aggregateUpdate(query, newValues: newValues)
        case .Otherwise:
            return otherwiseUpdate(query, newValues: newValues)
        case .Unique(let attribute, let value):
            return uniqueUpdate(query, newValues: newValues, attribute: attribute, value: value)
        }
    }
    
    func updateOperandsDirectly(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        for i in operands.indices {
            let result = operands[i].update(query, newValues: newValues)
            if result.err != nil {
                return result
            }
        }
        return .Ok()
    }
    
    func intersectionUpdate(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        for row in rows() {
            switch row {
            case .Ok(let row):
                if query.valueWithRow(row).boolValue {
                    let rowQuery = SelectExpressionFromRow(row)
                    for i in operands.indices {
                        let result = operands[i].update(rowQuery, newValues: newValues)
                        if result.err != nil {
                            return result
                        }
                    }
                }
            case .Err(let err):
                return .Err(err)
            }
        }
        return .Ok()
    }
    
    func differenceUpdate(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        for row in rows() {
            switch row {
            case .Ok(let row):
                if query.valueWithRow(row).boolValue {
                    let rowQuery = SelectExpressionFromRow(row)
                    let result = operands[0].update(rowQuery, newValues: newValues)
                    if result.err != nil {
                        return result
                    }
                }
            case .Err(let err):
                return .Err(err)
            }
        }
        return .Ok()
    }
    
    func selectUpdate(query: SelectExpression, newValues: Row, expression: SelectExpression) -> Result<Void, RelationError> {
        return operands[0].update(query *&& expression, newValues: newValues)
    }
    
    func equijoinUpdate(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        for row in rows() {
            switch row {
            case .Ok(let row):
                if query.valueWithRow(row).boolValue {
                    for i in operands.indices {
                        let operandAttributes = operands[i].scheme.attributes
                        let operandRow = row.rowWithAttributes(operandAttributes)
                        let operandNewValues = newValues.rowWithAttributes(operandAttributes)
                        if !operandNewValues.values.isEmpty {
                            let rowQuery = SelectExpressionFromRow(operandRow)
                            let result = operands[i].update(rowQuery, newValues: operandNewValues)
                            if result.err != nil {
                                return result
                            }
                        }
                    }
                }
            case .Err(let err):
                return .Err(err)
            }
        }
        return .Ok()
    }
    
    func renameUpdate(query: SelectExpression, newValues: Row, renames: [Attribute: Attribute]) -> Result<Void, RelationError> {
        let reverseRenames = renames.reversed
        let renamedQuery = query.withRenamedAttributes(reverseRenames)
        let renamedNewValues = newValues.renameAttributes(reverseRenames)
        return operands[0].update(renamedQuery, newValues: renamedNewValues)
    }
    
    func updateUpdate(query: SelectExpression, newValues: Row, myNewValues: Row) -> Result<Void, RelationError> {
        // Rewrite the query to eliminate attributes that we update. To do this,
        // map the expression to replace any attributes we update with the updated
        // value. Any other attributes can then be passed through to the underlying
        // relation for updates.
        let queryWithNewValues = query.mapTree({ (expr: SelectExpression) -> SelectExpression in
            switch expr {
            case let attr as Attribute:
                return myNewValues[attr] ?? attr
            default:
                return expr
            }
        })
        return operands[0].update(queryWithNewValues, newValues: newValues)
    }
    
    func aggregateUpdate(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        // TODO: Error, no-op, or pass through to underlying relation?
        return .Ok(())
    }
    
    func otherwiseUpdate(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        for i in operands.indices {
            switch operands[i].isEmpty {
            case .Ok(let empty):
                if !empty {
                    return operands[i].update(query, newValues: newValues)
                }
            case .Err(let err):
                return .Err(err)
            }
        }
        return .Ok()
    }
    
    func uniqueUpdate(query: SelectExpression, newValues: Row, attribute: Attribute, value: RelationValue) -> Result<Void, RelationError> {
        return isUnique(attribute, value).then({
            if $0 {
                return operands[0].update(query, newValues: newValues)
            } else {
                return .Ok()
            }
        })
    }
}

private class MutableSelectIntermediateRelation: IntermediateRelation, MutableSelectRelation {
    private var selectExpression: SelectExpression {
        get {
            if case .MutableSelect(let expression) = op {
                return expression
            } else {
                fatalError("Can't get the select expression from an IntermediateRelation with operator \(op)")
            }
        }
        set {
            if case .MutableSelect = op {
                let oldRelation = IntermediateRelation(op: op, operands: operands)
                op = .MutableSelect(newValue)
                
                let change = RelationChange(added: self - oldRelation, removed: oldRelation - self)
                notifyChangeObservers(change, kind: .DirectChange)
            } else {
                fatalError("Can't set the select expression from an IntermediateRelation with operator \(op)")
            }
            
        }
    }
}

extension Relation {
    public func mutableSelect(expression: SelectExpression) -> MutableSelectRelation {
        return MutableSelectIntermediateRelation(op: .MutableSelect(expression), operands: [self])
    }
}
