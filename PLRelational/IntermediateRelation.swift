//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc:
/// A generalized Relation which derives its value by performing some operation on other Relations.
/// This implements operations such as union, intersection, difference, join, etc.
open class IntermediateRelation: Relation, RelationDefaultChangeObserverImplementation {
    var op: Operator
    var operands: [Relation] {
        didSet {
            let objs = operands.flatMap(asObject)
            if objs.contains(where: { $0 === self }) {
                fatalError()
            }
        }
    }
    
    open var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    public var debugName: String?
    
    var derivative: RelationDerivative?
    var inTransaction = 0 // Like a refcount, incremented for begin, decremented for end, action at 0
    
    var didRegisterObservers = false
    
    public init(op: Operator, operands: [Relation]) {
        self.op = op
        self.operands = operands
        
        switch op {
        case .difference:
            precondition(operands.count == 2)
        case .project:
            precondition(operands.count == 1)
        case .select:
            precondition(operands.count == 1)
        case .equijoin:
            precondition(operands.count == 2)
        case .rename(let renames):
            precondition(operands.count == 1)
            precondition(self.scheme.attributes.count == operands[0].scheme.attributes.count, "Renaming \(operands[0].scheme) with renames \(renames) produced a collision")
        case .update:
            precondition(operands.count == 1)
        case .aggregate:
            precondition(operands.count == 1)
        default:
            precondition(operands.count > 0 && operands.count <= 2)
        }
        LogRelationCreation(self)
    }
    
    open var contentProvider: RelationContentProvider {
        return .intermediate(op, operands)
    }
}

/// :nodoc:
extension IntermediateRelation {
    public enum Operator {
        case union
        case intersection
        case difference
        
        case project(Scheme)
        case select(SelectExpression)
        case mutableSelect(SelectExpression)
        case equijoin([Attribute: Attribute])
        case rename([Attribute: Attribute])
        case update(Row)
        
        /// An arbitrary aggreagte function.
        /// The first associated value is the attribute that the final value will be stored under.
        /// The second associated value is the initial value that will be passed in the the function.
        /// The third associated value is the aggregate function itself. It receives the current
        /// value (either the initial value or what was returned by its last call) and an array of new
        /// rows to aggregate. This array is guaranteed to be nonempty.
        case aggregate(Attribute, RelationValue?, (RelationValue?, [Row]) -> Result<RelationValue, RelationError>)
        
        case otherwise
        case unique(Attribute, RelationValue)
    }
}

extension IntermediateRelation {
    static func union(_ operands: [Relation]) -> Relation {
        if operands.count == 1 {
            return operands[0]
        } else {
            return IntermediateRelation(op: .union, operands: operands)
        }
    }
    
    static func intersection(_ operands: [Relation]) -> Relation {
        if operands.count == 1 {
            return operands[0]
        } else {
            return IntermediateRelation(op: .intersection, operands: operands)
        }
    }
    
    /// A convenience initializer for aggregating functions which cannot fail and which always
    /// compare two values. If the initial value is nil, then the aggregate of an empty relation
    /// is empty, the aggregate of a relation containing a single row is the value stored in
    /// that row. The aggregate function is only called if there are two or more rows, and the
    /// first two calls will pass in the values of the first two rows.
    static func aggregate(_ relation: Relation, attribute: Attribute, initial: RelationValue?, agg: @escaping (RelationValue, RelationValue) -> RelationValue) -> Relation {
        return IntermediateRelation(op: .aggregate(attribute, initial, { (currentValue, rows) -> Result<RelationValue, RelationError> in
            if let currentValue = currentValue {
                return .Ok(rows.reduce(currentValue, { agg($0, $1[attribute]) }))
            } else {
                var value: RelationValue? = nil
                for row in rows {
                    let newValue = row[attribute]
                    if let unwrappedValue = value {
                        value = agg(unwrappedValue, newValue)
                    } else {
                        value = newValue
                    }
                }
                return .Ok(value!)
            }
        }), operands: [relation])
    }
}

/// :nodoc:
extension IntermediateRelation: RelationObserver {
    public func onAddFirstObserver() {
        let differentiator = RelationDifferentiator(relation: self)
        let derivative = differentiator.computeDerivative()
        self.derivative = derivative
        
        if !didRegisterObservers {
            for variable in derivative.allVariables where variable !== self {
                let proxy = WeakRelationObserverProxy(target: self)
                proxy.registerOn(variable, kinds: [.directChange])
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
    
    public func relationChanged(_ relation: Relation, change: RelationChange) {
        if let derivative = derivative {
            if inTransaction == 0 {
                derivative.clearVariables()
                derivative.setChange(change, forVariable: relation as! AnyObject & Relation)
                notifyChangeObservers(derivative.change, kind: .dependentChange)
            } else {
                derivative.setChange(change, forVariable: relation as! AnyObject & Relation)
            }
        }
    }
    
    public func transactionEnded() {
        inTransaction -= 1
        if let derivative = derivative , inTransaction == 0 {
            notifyChangeObservers(derivative.change, kind: .dependentChange)
        }
    }
}

extension IntermediateRelation {
    func otherOperands(_ excludingIndex: Int) -> [Relation] {
        var result = operands
        result.remove(at: excludingIndex)
        return result
    }
}

/// :nodoc:
extension IntermediateRelation {
    public var scheme: Scheme {
        switch op {
        case .project(let scheme):
            return scheme
        case .equijoin:
            let myAttributes = operands.reduce(Set(), { $0.union($1.scheme.attributes) })
            return Scheme(attributes: myAttributes)
        case .rename(let renames):
            let newAttributes = Set(operands[0].scheme.attributes.map({ renames[$0] ?? $0 }))
            return Scheme(attributes: newAttributes)
        case .aggregate(let attribute, _, _):
            return [attribute]
        default:
            return operands[0].scheme
        }
    }
}

extension IntermediateRelation {
    fileprivate func isUnique(_ attribute: Attribute, _ matching: RelationValue) -> Result<Bool, RelationError> {
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

/// :nodoc:
extension IntermediateRelation {
    public func contains(_ row: Row) -> Result<Bool, RelationError> {
        switch op {
        case .union:
            return unionContains(row)
        case .intersection:
            return intersectionContains(row)
        case .difference:
            return differenceContains(row)
        case .project:
            return projectContains(row)
        case .select(let expression):
            return selectContains(row, expression: expression)
        case .mutableSelect(let expression):
            return selectContains(row, expression: expression)
        case .equijoin:
            return equijoinContains(row)
        case .rename(let renames):
            return renameContains(row, renames: renames)
        case .update(let newValues):
            return updateContains(row, newValues: newValues)
        case .aggregate:
            return aggregateContains(row)
        case .otherwise:
            return otherwiseContains(row)
        case .unique(let attribute, let value):
            return uniqueContains(row, attribute: attribute, value: value)
        }
    }
    
    func unionContains(_ row: Row) -> Result<Bool, RelationError> {
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
    
    func intersectionContains(_ row: Row) -> Result<Bool, RelationError> {
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
    
    func differenceContains(_ row: Row) -> Result<Bool, RelationError> {
        return operands[0].contains(row).combine(operands[1].contains(row)).map({ $0 && !$1 })
    }
    
    func projectContains(_ row: Row) -> Result<Bool, RelationError> {
        return operands[0].select(row).isEmpty.map(!)
    }
    
    func selectContains(_ row: Row, expression: SelectExpression) -> Result<Bool, RelationError> {
        if !expression.valueWithRow(row).boolValue {
            return .Ok(false)
        } else {
            return operands[0].contains(row)
        }
    }
    
    func equijoinContains(_ row: Row) -> Result<Bool, RelationError> {
        return select(row).isEmpty.map(!)
    }
    
    func renameContains(_ row: Row, renames: [Attribute: Attribute]) -> Result<Bool, RelationError> {
        let renamedRow = row.renameAttributes(renames.inverted)
        return operands[0].contains(renamedRow)
    }
    
    func updateContains(_ row: Row, newValues: Row) -> Result<Bool, RelationError> {
        let newValuesScheme = Set(newValues.attributes)
        let newValueParts = row.rowWithAttributes(newValuesScheme)
        if newValueParts != newValues {
            return .Ok(false)
        }
        
        let untouchedAttributes = Set(operands[0].scheme.attributes.subtracting(newValues.attributes))
        let projected = operands[0].project(Scheme(attributes: untouchedAttributes))
        
        let remainingParts = row.rowWithAttributes(projected.scheme.attributes)
        return projected.contains(remainingParts)
    }
    
    func aggregateContains(_ row: Row) -> Result<Bool, RelationError> {
        return containsOk(rows(), { $0 == row })
    }
    
    func otherwiseContains(_ row: Row) -> Result<Bool, RelationError> {
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
    
    func uniqueContains(_ row: Row, attribute: Attribute, value: RelationValue) -> Result<Bool, RelationError> {
        return isUnique(attribute, value).then({
            if $0 {
                return operands[0].contains(row)
            } else {
                return .Ok(false)
            }
        })
    }
}

/// :nodoc:
extension IntermediateRelation {
    public func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        switch op {
        case .union:
            return updateOperandsDirectly(query, newValues: newValues)
        case .intersection:
            return intersectionUpdate(query, newValues: newValues)
        case .difference:
            return differenceUpdate(query, newValues: newValues)
        case .project:
            return updateOperandsDirectly(query, newValues: newValues)
        case .select(let expression):
            return selectUpdate(query, newValues: newValues, expression: expression)
        case .mutableSelect(let expression):
            return selectUpdate(query, newValues: newValues, expression: expression)
        case .equijoin:
            return equijoinUpdate(query, newValues: newValues)
        case .rename(let renames):
            return renameUpdate(query, newValues: newValues, renames: renames)
        case .update(let myNewValues):
            return updateUpdate(query, newValues: newValues, myNewValues: myNewValues)
        case .aggregate:
            return aggregateUpdate(query, newValues: newValues)
        case .otherwise:
            return otherwiseUpdate(query, newValues: newValues)
        case .unique(let attribute, let value):
            return uniqueUpdate(query, newValues: newValues, attribute: attribute, value: value)
        }
    }
    
    func updateOperandsDirectly(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        for i in operands.indices {
            let result = operands[i].update(query, newValues: newValues)
            if result.err != nil {
                return result
            }
        }
        return .Ok()
    }
    
    func intersectionUpdate(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
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
    
    func differenceUpdate(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
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
    
    func selectUpdate(_ query: SelectExpression, newValues: Row, expression: SelectExpression) -> Result<Void, RelationError> {
        return operands[0].update(query *&& expression, newValues: newValues)
    }
    
    func equijoinUpdate(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        for row in rows() {
            switch row {
            case .Ok(let row):
                if query.valueWithRow(row).boolValue {
                    for i in operands.indices {
                        let operandAttributes = operands[i].scheme.attributes
                        let operandRow = row.rowWithAttributes(operandAttributes)
                        let operandNewValues = newValues.rowWithAttributes(operandAttributes)
                        if !operandNewValues.isEmpty {
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
    
    func renameUpdate(_ query: SelectExpression, newValues: Row, renames: [Attribute: Attribute]) -> Result<Void, RelationError> {
        let reverseRenames = renames.inverted
        let renamedQuery = query.withRenamedAttributes(reverseRenames)
        let renamedNewValues = newValues.renameAttributes(reverseRenames)
        return operands[0].update(renamedQuery, newValues: renamedNewValues)
    }
    
    func updateUpdate(_ query: SelectExpression, newValues: Row, myNewValues: Row) -> Result<Void, RelationError> {
        // Rewrite the query to eliminate attributes that we update. To do this,
        // map the expression to replace any attributes we update with the updated
        // value. Any other attributes can then be passed through to the underlying
        // relation for updates.
        let queryWithNewValues = query.mapTree({ (expr: SelectExpression) -> SelectExpression in
            switch expr {
            case let attr as Attribute:
                let newValue = myNewValues[attr]
                return newValue == .notFound ? attr : newValue
            default:
                return expr
            }
        })
        return operands[0].update(queryWithNewValues, newValues: newValues)
    }
    
    func aggregateUpdate(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        // TODO: Error, no-op, or pass through to underlying relation?
        return .Ok(())
    }
    
    func otherwiseUpdate(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
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
    
    func uniqueUpdate(_ query: SelectExpression, newValues: Row, attribute: Attribute, value: RelationValue) -> Result<Void, RelationError> {
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
    fileprivate var selectExpression: SelectExpression {
        get {
            if case .mutableSelect(let expression) = op {
                return expression
            } else {
                fatalError("Can't get the select expression from an IntermediateRelation with operator \(op)")
            }
        }
        set {
            if case .mutableSelect = op {
                let oldRelation = IntermediateRelation(op: op, operands: operands)
                op = .mutableSelect(newValue)
                
                let change = RelationChange(added: self - oldRelation, removed: oldRelation - self)
                notifyChangeObservers(change, kind: .directChange)
            } else {
                fatalError("Can't set the select expression from an IntermediateRelation with operator \(op)")
            }
            
        }
    }
}

extension Relation {
    
    // MARK: Mutable select
    
    public func mutableSelect(_ expression: SelectExpression) -> MutableSelectRelation {
        return MutableSelectIntermediateRelation(op: .mutableSelect(expression), operands: [self])
    }
}
