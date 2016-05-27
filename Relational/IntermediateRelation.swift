
/// A generalized Relation which derives its value by performing some operation on other Relations.
/// This implements operations such as union, intersection, difference, join, etc.
class IntermediateRelation: Relation, RelationDefaultChangeObserverImplementation {
    let op: Operator
    var operands: [Relation]
    
    var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    init(op: Operator, operands: [Relation]) {
        self.op = op
        self.operands = operands
        
        switch op {
        case .Difference:
            // TODO: handle more than two operands? [A, B, C] could turn into A - B - C somewhat sensibly.
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
            precondition(operands.count > 0)
        }
        LogRelationCreation(self)
    }
}

extension IntermediateRelation {
    enum Operator {
        case Union
        case Intersection
        case Difference
        
        case Project(Scheme)
        case Select(SelectExpression)
        case Equijoin([Attribute: Attribute])
        case Rename([Attribute: Attribute])
        case Update(Row)
        case Aggregate(Attribute, RelationValue?, (RelationValue?, RelationValue) -> Result<RelationValue, RelationError>)
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

extension IntermediateRelation {
    func onAddFirstObserver() {
        for (index, relation) in operands.enumerate() {
            relation.addWeakChangeObserver(self, call: { $0.observeChange($1, operandIndex: index) })
        }
    }
    
    private func otherOperands(excludingIndex: Int) -> [Relation] {
        var result = operands
        result.removeAtIndex(excludingIndex)
        return result
    }
    
    private func observeChange(change: RelationChange, operandIndex: Int) {
        let myAdded: Relation?
        let myRemoved: Relation?
        
        switch op {
        case .Union:
            // Adding a row to one part of a union adds that row to the union iff the row
            // isn't already present in one of the other relations. Same for removals.
            let others = otherOperands(operandIndex)
            myAdded = change.added?.difference(IntermediateRelation.union(others))
            myRemoved = change.removed?.difference(IntermediateRelation.union(others))
        case .Intersection:
            // Adding or removing a row from one part of an intersection alters the intersection
            // iff the row is already in another part of the intersection.
            let others = otherOperands(operandIndex)
            myAdded = change.added?.intersection(IntermediateRelation.intersection(others))
            myRemoved = change.removed?.intersection(IntermediateRelation.intersection(others))
        case .Difference:
            // When the first one changes, our changes are the same, minus the second.
            // When the second one changes, then changes are reversed and intersected
            // with the first.
            if operandIndex == 0 {
                myAdded = change.added?.difference(operands[1])
                myRemoved = change.removed?.difference(operands[1])
            } else {
                myAdded = change.removed?.intersection(operands[0])
                myRemoved = change.added?.intersection(operands[0])
            }
        case .Project(let scheme):
            (myAdded, myRemoved) = changesForProjection(change, scheme: scheme)
        case .Select(let expression):
            // Our changes are equal to the underlying changes with the same select applied.
            myAdded = change.added?.select(expression)
            myRemoved = change.removed?.select(expression)
        case .Equijoin(let matching):
            // Changes in a relation are joined with the other one to produce the final result.
            if operandIndex == 0 {
                myAdded = change.added?.equijoin(operands[1], matching: matching)
                myRemoved = change.removed?.equijoin(operands[1], matching: matching)
            } else {
                myAdded = change.added.map({ operands[0].equijoin($0, matching: matching) })
                myRemoved = change.removed.map({ operands[0].equijoin($0, matching: matching) })
            }
        case .Rename(let renames):
            // Changes are the same, but renamed.
            myAdded = change.added?.renameAttributes(renames)
            myRemoved = change.removed?.renameAttributes(renames)
        case .Update(let newValues):
            // Our updates are equal to the projected updates joined with our newValues.
            let untouchedScheme = Scheme(attributes: Set(operands[0].scheme.attributes.subtract(newValues.values.keys)))
            let (projectedAdded, projectedRemoved) = changesForProjection(change, scheme: untouchedScheme)
            myAdded = projectedAdded?.join(ConcreteRelation(newValues))
            myRemoved = projectedRemoved?.project(untouchedScheme).join(ConcreteRelation(newValues))
        case .Aggregate(let attribute, let initialValue, let aggregateFunction):
            // TODO: We're using the dumb and inefficient approach for now.  We should instead
            // cache the computed aggregate value and inspect the added/removed rows to determine
            // if the aggregate value has changed
            
            var preChangeRelation = operands[0]
            if let added = change.added {
                preChangeRelation = preChangeRelation.difference(added)
            }
            if let removed = change.removed {
                preChangeRelation = preChangeRelation.union(removed)
            }
            let previousAgg = IntermediateRelation(op: .Aggregate(attribute, initialValue, aggregateFunction), operands: [preChangeRelation])
            
            if self.intersection(previousAgg).isEmpty.ok == true {
                myAdded = self
                myRemoved = previousAgg
            } else {
                myAdded = nil
                myRemoved = nil
            }
        }
        
        notifyChangeObservers(RelationChange(added: myAdded, removed: myRemoved))
    }
    
    private func changesForProjection(change: RelationChange, scheme: Scheme) -> (Relation?, Relation?) {
        // Adds to the underlying relation are adds to the projected relation
        // if there were no matching rows in the relation before. To compute
        // that, project the changes, then subtract the pre-change relation,
        // which is the post-change relation minus additions and plus removals.
        //
        // Removes are the same, except they subtract the post-change relation,
        // which is just self.
        var preChangeRelation = operands[0]
        if let added = change.added {
            preChangeRelation = preChangeRelation.difference(added)
        }
        if let removed = change.removed {
            preChangeRelation = preChangeRelation.union(removed)
        }
        
        let myAdded = change.added?.project(scheme).difference(preChangeRelation.project(scheme))
        let myRemoved = change.removed?.project(scheme).difference(self)
        return (myAdded, myRemoved)
    }
}

extension IntermediateRelation {
    var scheme: Scheme {
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
    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        let data = LogRelationIterationBegin(self)
        let generator: AnyGenerator<Result<Row, RelationError>>
        switch op {
        case .Union:
            generator = unionRows()
        case .Intersection:
            generator = intersectionRows()
        case .Difference:
            generator = differenceRows()
        case .Project(let scheme):
            generator = projectRows(scheme)
        case .Select(let expression):
            generator = selectRows(expression)
        case .Equijoin(let matching):
            generator = equijoinRows(matching)
        case .Rename(let renames):
            generator = renameRows(renames)
        case .Update(let newValues):
            generator = updateRows(newValues)
        case .Aggregate(let attribute, let initialValue, let aggregateFunction):
            generator = aggregateRows(attribute, initialValue: initialValue, agg: aggregateFunction)
        }
        return LogRelationIterationReturn(data, generator)
    }
    
    private func unionRows() -> AnyGenerator<Result<Row, RelationError>> {
        // In common usage, we tend to place relations where contains() is expensive
        // (like SQLiteRelation) on the left side of the union. Because of that, we
        // move through the operands such that we do contains checks on the later ones
        // while iterating through the earlier ones, not vice versa.
        let generators = operands.enumerate().map({ index, relation -> AnyGenerator<Result<Row, RelationError>> in
            let rows = relation.rows()
            let remainder = operands.suffixFrom(index + 1)
            if remainder.count == 0 {
                return rows
            } else {
                return AnyGenerator(rows.lazy.flatMap({ row -> Result<Row, RelationError>? in
                    switch row {
                    case .Ok(let row):
                        for r in remainder {
                            switch r.contains(row) {
                            case .Ok(let contains):
                                if contains {
                                    return nil
                                }
                            case .Err(let err):
                                return .Err(err)
                            }
                        }
                        return .Ok(row)
                    case .Err:
                        return row
                    }
                }).generate())
            }
        })
        return AnyGenerator(generators.flatten().generate())
    }
    
    private func intersectionRows() -> AnyGenerator<Result<Row, RelationError>> {
        let first = operands[0]
        let rest = operands.suffixFrom(1)
        return AnyGenerator(first.rows().lazy.flatMap({ row in
            switch row {
            case .Ok(let row):
                for r in rest {
                    switch r.contains(row) {
                    case .Ok(let contains):
                        if !contains {
                            return nil
                        }
                    case .Err(let err):
                        return .Err(err)
                    }
                }
                return .Ok(row)
            case .Err:
                return row
            }
        }).generate())
    }
    
    private func differenceRows() -> AnyGenerator<Result<Row, RelationError>> {
        let first = operands[0]
        let rest = operands.suffixFrom(1)
        return AnyGenerator(first.rows().lazy.flatMap({ row in
            switch row {
            case .Ok(let row):
                for r in rest {
                    switch r.contains(row) {
                    case .Ok(let contains):
                        if contains {
                            return nil
                        }
                    case .Err(let err):
                        return .Err(err)
                    }
                }
                return .Ok(row)
            case .Err:
                return row
            }
        }).generate())
    }
    
    private func projectRows(scheme: Scheme) -> AnyGenerator<Result<Row, RelationError>> {
        let gen = operands[0].rows()
        var seen: Set<Row> = []
        return AnyGenerator(body: {
            while let row = gen.next() {
                switch row {
                case .Ok(let row):
                    let subvalues = self.scheme.attributes.map({ ($0, row[$0]) })
                    let newRow = Row(values: Dictionary(subvalues))
                    if !seen.contains(newRow) {
                        seen.insert(newRow)
                        return .Ok(newRow)
                    }
                case .Err:
                    return row
                }
            }
            return nil
        })
    }
    
    private func selectRows(expression: SelectExpression) -> AnyGenerator<Result<Row, RelationError>> {
        return AnyGenerator(operands[0].rows().lazy.filter({ row in
            switch row {
            case .Ok(let row):
                return expression.valueWithRow(row).boolValue
            case .Err:
                return true
            }
        }).generate())
    }
    
    private func equijoinRows(matching: [Attribute: Attribute]) -> AnyGenerator<Result<Row, RelationError>> {
        // For an optimal (least memory usage) join, we want to figure out which of the joined relations
        // is smaller, use that one to populate the hash table, then scan the other one. Figuring out
        // relation size is non-trivial, though. Instead, we'll scan both relations in parallel, saving
        // what we find. When we hit the end of one, that's the smaller one. Load that one's rows (now
        // in memory) into the hash table. Join with the rows of the other one, starting with the ones
        // in memory and adding on the remaining rows we haven't yet read out of the second relation.
        var aCachedRows: [Row] = []
        var bCachedRows: [Row] = []
        
        let aAttributes = Array(matching.keys)
        let bAttributes = Array(matching.values)
        
        let aGen = operands[0].rows()
        let bGen = operands[1].rows()
        
        var smallerRows: [Row]!
        var smallerAttributes: [Attribute]!
        var smallerToLargerRenaming: [Attribute: Attribute]!
        var largerCachedRows: [Row]!
        var largerRemainderGenerator: AnyGenerator<Result<Row, RelationError>>!
        var largerAttributes: [Attribute]!
        var largerToSmallerRenaming: [Attribute: Attribute]!
        var largerRelation: Relation!
        
        while true {
            if let aRow = aGen.next() {
                switch aRow {
                case .Ok(let row):
                    aCachedRows.append(row)
                case .Err(let err):
                    return AnyGenerator(GeneratorOfOne(Result<Row, RelationError>.Err(err)))
                }
            } else {
                smallerRows = aCachedRows
                smallerAttributes = aAttributes
                smallerToLargerRenaming = matching
                largerCachedRows = bCachedRows
                largerRemainderGenerator = bGen
                largerAttributes = bAttributes
                largerToSmallerRenaming = matching.reversed
                largerRelation = operands[1]
                break
            }
            if let bRow = bGen.next() {
                switch bRow {
                case .Ok(let row):
                    bCachedRows.append(row)
                case .Err(let err):
                    return AnyGenerator(GeneratorOfOne(Result<Row, RelationError>.Err(err)))
                }
            } else {
                smallerRows = bCachedRows
                smallerAttributes = bAttributes
                smallerToLargerRenaming = matching.reversed
                largerCachedRows = aCachedRows
                largerRemainderGenerator = aGen
                largerAttributes = aAttributes
                largerToSmallerRenaming = matching
                largerRelation = operands[0]
                break
            }
        }
        
        // Joining with an empty relation produces an empty relation. Short circuit that.
        if smallerRows.isEmpty {
            return AnyGenerator(EmptyGenerator())
        }
        
        // Joining with a single row is equivalent to a select and then combining the output
        // with that single row, but the select operation is potentially faster.
        if smallerRows.count == 1 {
            let smallerRow = smallerRows[0]
            let smallerKey = smallerRow.rowWithAttributes(smallerAttributes)
            let largerKey = smallerKey.renameAttributes(smallerToLargerRenaming)
            let largerFiltered = largerRelation.select(largerKey)
            return AnyGenerator(largerFiltered.rows().lazy.map({ (row: Result<Row, RelationError>) -> Result<Row, RelationError> in
                return row.map({ (row: Row) -> Row in
                    Row(values: row.values + smallerRow.values)
                })
            }).generate())
        }
        // Potential TODO: if smallerRows is small but has more than one element,
        // it may still be better to turn that into a select as in the == 1 case,
        // rather than scanning the entire other relation.
        
        // This maps join keys in `smallerRows` to entire rows.
        var keyed: [Row: [Row]] = [:]
        for row in smallerRows {
            let joinKey = row.rowWithAttributes(smallerAttributes)
            if keyed[joinKey] != nil {
                keyed[joinKey]!.append(row)
            } else {
                keyed[joinKey] = [row]
            }
        }
        
        let cachedJoined = largerCachedRows.lazy.flatMap({ row -> [Result<Row, RelationError>] in
            let joinKey = row.rowWithAttributes(largerAttributes).renameAttributes(largerToSmallerRenaming)
            guard let smallerRows = keyed[joinKey] else { return [] }
            return smallerRows.map({ .Ok(Row(values: $0.values + row.values)) })
        })
        
        let remainderJoined = largerRemainderGenerator.lazy.flatMap({ rowResult -> [Result<Row, RelationError>] in
            guard let row = rowResult.ok else { return [rowResult] }
            let joinKey = row.rowWithAttributes(largerAttributes).renameAttributes(largerToSmallerRenaming)
            guard let smallerRows = keyed[joinKey] else { return [] }
            return smallerRows.map({ .Ok(Row(values: $0.values + row.values)) })
        })
        
        let concatenated = cachedJoined.generate().concat(remainderJoined.generate())
        return AnyGenerator(concatenated)
    }
    
    private func renameRows(renames: [Attribute: Attribute]) -> AnyGenerator<Result<Row, RelationError>> {
        return AnyGenerator(
            operands[0]
                .rows()
                .lazy
                .map({ $0.map({ $0.renameAttributes(renames) }) })
                .generate())
    }
    
    private func updateRows(newValues: Row) -> AnyGenerator<Result<Row, RelationError>> {
        let untouchedAttributes = Set(operands[0].scheme.attributes.subtract(newValues.values.keys))
        let projected = operands[0].project(Scheme(attributes: untouchedAttributes))
        return AnyGenerator(projected.rows().lazy.map({ (row: Result<Row, RelationError>) -> Result<Row, RelationError> in
            return row.map({ (row: Row) -> Row in
                return Row(values: row.values + newValues.values)
            })
        }).generate())
    }
    
    private func aggregateRows(attribute: Attribute, initialValue: RelationValue?, agg: (RelationValue?, RelationValue) -> Result<RelationValue, RelationError>) -> AnyGenerator<Result<Row, RelationError>> {
        var done = false
        return AnyGenerator(body: {
            guard !done else { return nil }
            
            var soFar: RelationValue? = initialValue
            for row in self.operands[0].rows() {
                switch row {
                case .Ok(let row):
                    let newValue = row[attribute]
                    let aggregated = agg(soFar, newValue)
                    switch aggregated {
                    case .Ok(let value):
                        soFar = value
                    case .Err(let err):
                        return .Err(err)
                    }
                case .Err(let err):
                    return .Err(err)
                }
            }
            done = true
            return soFar.map({ .Ok(Row(values: [attribute: $0])) })
        })
    }
}

extension IntermediateRelation {
    func contains(row: Row) -> Result<Bool, RelationError> {
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
        case .Equijoin:
            return equijoinContains(row)
        case .Rename(let renames):
            return renameContains(row, renames: renames)
        case .Update(let newValues):
            return updateContains(row, newValues: newValues)
        case .Aggregate:
            return aggregateContains(row)
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
}

extension IntermediateRelation {
    func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
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
        case .Equijoin:
            return equijoinUpdate(query, newValues: newValues)
        case .Rename(let renames):
            return renameUpdate(query, newValues: newValues, renames: renames)
        case .Update(let myNewValues):
            return updateUpdate(query, newValues: newValues, myNewValues: myNewValues)
        case .Aggregate:
            return aggregateUpdate(query, newValues: newValues)
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
}
