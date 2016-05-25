class UnionRelation: Relation, RelationDefaultChangeObserverImplementation {
    var a: Relation
    var b: Relation
    
    var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    init(a: Relation, b: Relation) {
        precondition(a.scheme == b.scheme)
        self.a = a
        self.b = b
    }
    
    var scheme: Scheme {
        return a.scheme
    }
    
    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        let data = LogRelationIterationBegin(self)
        // In common usage, we tend to place relations where contains() is expensive
        // (like SQLiteRelation) on the left side of the union. Because of that, we
        // represent the union as (b + (a - b)) rather than (a + (b - a)).
        let aUnique = a.rows().lazy.flatMap({ (row: Result<Row, RelationError>) -> Result<Row, RelationError>? in
            switch row {
            case .Ok(let row):
                switch self.b.contains(row) {
                case .Ok(let contains):
                    return contains ? nil : .Ok(row)
                case .Err(let err):
                    return .Err(err)
                }
            case .Err:
                return row
            }
        })
        return LogRelationIterationReturn(data, AnyGenerator(aUnique.generate().concat(b.rows())))
    }
    
    func contains(row: Row) -> Result<Bool, RelationError> {
        return a.contains(row).combine(b.contains(row)).map({ $0 || $1 })
    }
    
    func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let aResult = a.update(query, newValues: newValues)
        let bResult = b.update(query, newValues: newValues)
        return aResult.and(bResult)
    }
    
    // Special case union(UnionRelation(..., ConcreteRelation), ConcreteRelation) to avoid
    // building up deep layers.
    func union(other: Relation) -> Relation {
        if let concreteOther = other as? ConcreteRelation {
            if let concreteMine = a as? ConcreteRelation {
                let concreteCombined = ConcreteRelation(scheme: scheme, values: concreteMine.values.union(concreteOther.values))
                return UnionRelation(a: concreteCombined, b: b)
            }
            if let concreteMine = b as? ConcreteRelation {
                let concreteCombined = ConcreteRelation(scheme: scheme, values: concreteMine.values.union(concreteOther.values))
                return UnionRelation(a: a, b: concreteCombined)
            }
        }
        return UnionRelation(a: self, b: other)
    }
    
    func onAddFirstObserver() {
        a.addWeakChangeObserver(self, call: { $0.observeChange($1, otherRelation: $0.b) })
        b.addWeakChangeObserver(self, call: { $0.observeChange($1, otherRelation: $0.a) })
    }
    
    private func observeChange(change: RelationChange, otherRelation: Relation) {
        // Adding a row to one side of a union adds that row to the union iff the
        // row isn't already in the other side. Same for deleting a row. Thus, our
        // change is the original change with the other relation subtracted.
        let unionChange = RelationChange(
            added: change.added?.difference(otherRelation),
            removed: change.removed?.difference(otherRelation))
        notifyChangeObservers(unionChange)
    }
}

class IntersectionRelation: Relation, RelationDefaultChangeObserverImplementation {
    var a: Relation
    var b: Relation
    
    var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    init(a: Relation, b: Relation) {
        precondition(a.scheme == b.scheme)
        self.a = a
        self.b = b
    }
    
    var scheme: Scheme {
        return a.scheme
    }
    
    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        let data = LogRelationIterationBegin(self)
        let aGen = a.rows()
        return LogRelationIterationReturn(data, AnyGenerator(body: {
            while let row = aGen.next() {
                switch row {
                case .Ok(let row):
                    let contains = self.b.contains(row)
                    switch contains {
                    case .Ok(let contains):
                        if contains {
                            return .Ok(row)
                        }
                    case .Err(let error):
                        return .Err(error)
                    }
                case .Err:
                    return row
                }
            }
            return nil
        }))
    }
    
    func contains(row: Row) -> Result<Bool, RelationError> {
        return a.contains(row).combine(b.contains(row)).map({ $0 && $1 })
    }
    
    func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let rowsToUpdate = mapOk(self.select(query).rows(), { $0 })
        return rowsToUpdate.then({ rows in
            for row in rows {
                let rowQuery = SelectExpressionFromRow(row)
                let resultA = a.update(rowQuery, newValues: newValues)
                if let err = resultA.err {
                    return .Err(err)
                }
                let resultB = b.update(rowQuery, newValues: newValues)
                if let err = resultB.err {
                    return .Err(err)
                }
            }
            return .Ok()
        })
    }
    
    func onAddFirstObserver() {
        a.addWeakChangeObserver(self, call: { $0.observeChange($1, otherRelation: $0.b) })
        b.addWeakChangeObserver(self, call: { $0.observeChange($1, otherRelation: $0.a) })
    }
    
    private func observeChange(change: RelationChange, otherRelation: Relation) {
        // Adding a row to one side of an intersection adds that row to the union iff the
        // row is already in the other side. Same for deleting a row. Thus, our
        // change is the original change intersected with the other relation.
        let intersectionChange = RelationChange(
            added: change.added?.intersection(otherRelation),
            removed: change.removed?.intersection(otherRelation))
        notifyChangeObservers(intersectionChange)
    }
}

class DifferenceRelation: Relation, RelationDefaultChangeObserverImplementation {
    var a: Relation
    var b: Relation

    var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    init(a: Relation, b: Relation) {
        precondition(a.scheme == b.scheme)
        self.a = a
        self.b = b
    }
    
    var scheme: Scheme {
        return a.scheme
    }
    
    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        let data = LogRelationIterationBegin(self)
        let aGen = a.rows()
        return LogRelationIterationReturn(data, AnyGenerator(body: {
            while let row = aGen.next() {
                switch row {
                case .Ok(let row):
                    let contains = self.b.contains(row)
                    switch contains {
                    case .Ok(let contains):
                        if !contains {
                            return .Ok(row)
                        }
                    case .Err(let error):
                        return .Err(error)
                    }
                case .Err:
                    return row
                }
            }
            return nil
        }))
    }
    
    func contains(row: Row) -> Result<Bool, RelationError> {
        return a.contains(row).combine(b.contains(row)).map({ $0 && !$1 })
    }
    
    func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let rowsToUpdate = mapOk(self.select(query).rows(), { $0 })
        return rowsToUpdate.then({ rows in
            for row in rows {
                let rowQuery = SelectExpressionFromRow(row)
                let result = a.update(rowQuery, newValues: newValues)
                if let err = result.err {
                    return .Err(err)
                }
            }
            return .Ok()
        })
    }
    
    func onAddFirstObserver() {
        a.addWeakChangeObserver(self, method: self.dynamicType.observeChangeA)
        b.addWeakChangeObserver(self, method: self.dynamicType.observeChangeB)
    }
    
    private func observeChangeA(change: RelationChange) {
        // When a changes, our changes are the same, minus the entries in b.
        let intersectionChange = RelationChange(
            added: change.added?.difference(b),
            removed: change.removed?.difference(b))
        notifyChangeObservers(intersectionChange)
    }
    
    private func observeChangeB(change: RelationChange) {
        // When b changes, our changes are switched (adds are removes, removes are adds)
        // and intersected with the entries in a.
        let intersectionChange = RelationChange(
            added: change.removed?.intersection(a),
            removed: change.added?.intersection(a))
        notifyChangeObservers(intersectionChange)
    }
}

class ProjectRelation: Relation, RelationDefaultChangeObserverImplementation {
    var relation: Relation
    let scheme: Scheme
    
    var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    init(relation: Relation, scheme: Scheme) {
        precondition(scheme.attributes.isSubsetOf(relation.scheme.attributes))
        self.relation = relation
        self.scheme = scheme
    }
    
    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        let data = LogRelationIterationBegin(self)
        let gen = relation.rows()
        var seen: Set<Row> = []
        return LogRelationIterationReturn(data, AnyGenerator(body: {
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
        }))
    }
    
    func contains(row: Row) -> Result<Bool, RelationError> {
        return relation.select(row).isEmpty.map(!)
    }
    
    func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        return relation.update(query, newValues: newValues)
    }
    
    func onAddFirstObserver() {
        relation.addWeakChangeObserver(self, method: self.dynamicType.observeChange)
    }
    
    private func observeChange(change: RelationChange) {
        // Adds to the underlying relation are adds to the projected relation
        // if there were no matching rows in the relation before. To compute
        // that, project the changes, then subtract the pre-change relation,
        // which is the post-change relation minus additions and plus removals.
        //
        // Removes are the same, except they subtract the post-change relation,
        // which is just self.
        var preChangeRelation = relation
        if let added = change.added {
            preChangeRelation = preChangeRelation.difference(added)
        }
        if let removed = change.removed {
            preChangeRelation = preChangeRelation.union(removed)
        }
        
        let projectChange = RelationChange(
            added: change.added?.project(scheme).difference(preChangeRelation.project(scheme)),
            removed: change.removed?.project(scheme).difference(self))
        notifyChangeObservers(projectChange)
    }
}

class SelectRelation: Relation, RelationDefaultChangeObserverImplementation {
    var relation: Relation
    let query: SelectExpression
    
    var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    init(relation: Relation, query: SelectExpression) {
        self.relation = relation
        self.query = query
    }
    
    var scheme: Scheme {
        return relation.scheme
    }
    
    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        let data = LogRelationIterationBegin(self)
        let gen = relation.rows()
        return LogRelationIterationReturn(data, AnyGenerator(body: {
            while let row = gen.next() {
                switch row {
                case .Ok(let row):
                    if self.query.valueWithRow(row).boolValue {
                        return .Ok(row)
                    }
                case .Err:
                    return row
                }
            }
            return nil
        }))
    }
    
    func contains(row: Row) -> Result<Bool, RelationError> {
        if !self.query.valueWithRow(row).boolValue {
            return .Ok(false)
        } else {
            return relation.contains(row)
        }
    }
    
    func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        return relation.update(query *&& self.query, newValues: newValues)
    }
    
    func select(query: SelectExpression) -> Relation {
        let combinedQuery = self.query *&& query
        return SelectRelation(relation: self.relation, query: combinedQuery)
    }
    
    func onAddFirstObserver() {
        relation.addWeakChangeObserver(self, method: self.dynamicType.observeChange)
    }
    
    private func observeChange(change: RelationChange) {
        // Our changes are equal to the underlying changes with the same select applied.
        let selectChange = RelationChange(
            added: change.added?.select(query),
            removed: change.removed?.select(query))
        notifyChangeObservers(selectChange)
    }
}

class EquijoinRelation: Relation, RelationDefaultChangeObserverImplementation {
    var a: Relation
    var b: Relation
    let matching: [Attribute: Attribute]
    
    var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    init(a: Relation, b: Relation, matching: [Attribute: Attribute]) {
        self.a = a
        self.b = b
        self.matching = matching
    }
    
    var scheme: Scheme {
        return Scheme(attributes: a.scheme.attributes.union(b.scheme.attributes))
    }

    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        let data = LogRelationIterationBegin(self)
        
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
        
        let aGen = a.rows()
        let bGen = b.rows()
        
        var smallerRows: [Row]!
        var smallerAttributes: [Attribute]!
        var largerCachedRows: [Row]!
        var largerRemainderGenerator: AnyGenerator<Result<Row, RelationError>>!
        var largerAttributes: [Attribute]!
        var largerToSmallerRenaming: [Attribute: Attribute]!
        
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
                largerCachedRows = bCachedRows
                largerRemainderGenerator = bGen
                largerAttributes = bAttributes
                largerToSmallerRenaming = matching.reversed
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
                largerCachedRows = aCachedRows
                largerRemainderGenerator = aGen
                largerAttributes = aAttributes
                largerToSmallerRenaming = matching
                break
            }
        }
        
        // Potential TODO: if smallerRows is really small (like, one entry) then we might want to
        // turn this into a select operation to save scanning the whole other relation.
        
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
        return LogRelationIterationReturn(data, AnyGenerator(concatenated))
    }
    
    func contains(row: Row) -> Result<Bool, RelationError> {
        return self.select(row).isEmpty.map(!)
    }
    
    func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let rowsToUpdate = mapOk(self.select(query).rows(), { $0 })
        return rowsToUpdate.then({ rows in
            for row in rows {
                let aRow = row.rowWithAttributes(a.scheme.attributes)
                let aNewValues = newValues.rowWithAttributes(a.scheme.attributes)
                if aNewValues.values.count > 0 {
                    let resultA = a.update(SelectExpressionFromRow(aRow), newValues: aNewValues)
                    if let err = resultA.err {
                        return .Err(err)
                    }
                }
                
                let bRow = row.rowWithAttributes(b.scheme.attributes)
                let bNewValues = newValues.rowWithAttributes(b.scheme.attributes)
                if bNewValues.values.count > 0 {
                    let resultB = b.update(SelectExpressionFromRow(bRow), newValues: bNewValues)
                    if let err = resultB.err {
                        return .Err(err)
                    }
                }
            }
            return .Ok()
        })
    }
    
    func onAddFirstObserver() {
        a.addWeakChangeObserver(self, method: self.dynamicType.observeChangeA)
        b.addWeakChangeObserver(self, method: self.dynamicType.observeChangeB)
    }
    
    private func observeChangeA(change: RelationChange) {
        // Changes to the underlying relations are joined with the unchanged relation
        // to produce the changes in the join relation.
        let joinChange = RelationChange(
            added: change.added?.equijoin(b, matching: matching),
            removed: change.removed?.equijoin(b, matching: matching))
        notifyChangeObservers(joinChange)
    }
    
    private func observeChangeB(change: RelationChange) {
        let joinChange = RelationChange(
            added: change.added.map({ a.equijoin($0, matching: matching) }),
            removed: change.removed.map({ a.equijoin($0, matching: matching) }))
        notifyChangeObservers(joinChange)
    }
}

class RenameRelation: Relation, RelationDefaultChangeObserverImplementation {
    var relation: Relation
    let renames: [Attribute: Attribute]
    
    var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    init(relation: Relation, renames: [Attribute: Attribute]) {
        self.relation = relation
        self.renames = renames
    }
    
    var scheme: Scheme {
        let newAttributes = Set(relation.scheme.attributes.map({ renames[$0] ?? $0 }))
        precondition(newAttributes.count == relation.scheme.attributes.count, "Renaming \(relation.scheme) with renames \(renames) produced a collision")
        
        return Scheme(attributes: newAttributes)
    }
    
    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        let data = LogRelationIterationBegin(self)
        return LogRelationIterationReturn(data, AnyGenerator(
            relation
                .rows()
                .lazy
                .map({ $0.map({ $0.renameAttributes(self.renames) }) })
                .generate()))
    }
    
    func contains(row: Row) -> Result<Bool, RelationError> {
        return relation.contains(row.renameAttributes(renames.reversed))
    }
    
    func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let reverseRenames = self.renames.reversed
        let renamedQuery = query.withRenamedAttributes(reverseRenames)
        let renamedNewValues = newValues.renameAttributes(reverseRenames)
        return relation.update(renamedQuery, newValues: renamedNewValues)
    }
    
    func onAddFirstObserver() {
        relation.addWeakChangeObserver(self, method: self.dynamicType.observeChange)
    }
    
    private func observeChange(change: RelationChange) {
        // Changes are the same, but renamed.
        let renameChange = RelationChange(
            added: change.added?.renameAttributes(renames),
            removed: change.removed?.renameAttributes(renames))
        notifyChangeObservers(renameChange)
    }
}

class UpdateRelation: Relation, RelationDefaultChangeObserverImplementation {
    var projected: Relation
    let newValues: Row
    
    let scheme: Scheme
    
    var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    init(relation: Relation, newValues: Row) {
        let untouchedAttributes = Set(relation.scheme.attributes.subtract(newValues.values.keys))
        self.projected = relation.project(Scheme(attributes: untouchedAttributes))
        self.newValues = newValues
        self.scheme = relation.scheme
    }
    
    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        let data = LogRelationIterationBegin(self)
        return LogRelationIterationReturn(data, AnyGenerator(projected.rows().lazy.map({ (row: Result<Row, RelationError>) -> Result<Row, RelationError> in
            return row.map({ (row: Row) -> Row in
                return Row(values: row.values + self.newValues.values)
            })
        }).generate()))
    }
    
    func contains(row: Row) -> Result<Bool, RelationError> {
        let newValuesScheme = Set(newValues.values.keys)
        let newValueParts = row.rowWithAttributes(newValuesScheme)
        if newValueParts != newValues {
            return .Ok(false)
        }
        
        let remainingParts = row.rowWithAttributes(projected.scheme.attributes)
        return projected.contains(remainingParts)
    }
    
    func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        // Rewrite the query to eliminate attributes that we update. To do this,
        // map the expression to replace any attributes we update with the updated
        // value. Any other attributes can then be passed through to the underlying
        // relation for updates.
        let queryWithNewValues = query.mapTree({ (expr: SelectExpression) -> SelectExpression in
            switch expr {
            case let attr as Attribute:
                return self.newValues[attr] ?? attr
            default:
                return expr
            }
        })
        return projected.update(queryWithNewValues, newValues: newValues)
    }
    
    func onAddFirstObserver() {
        projected.addWeakChangeObserver(self, method: self.dynamicType.observeChange)
    }
    
    private func observeChange(change: RelationChange) {
        // Our updates are equal to the projected updates joined with our newValues.
        let updateChange = RelationChange(
            added: change.added?.join(ConcreteRelation(newValues)),
            removed: change.removed?.join(ConcreteRelation(newValues)))
        notifyChangeObservers(updateChange)
    }
}

class AggregateRelation: Relation, RelationDefaultChangeObserverImplementation {
    let relation: Relation
    let attribute: Attribute
    let initialValue: RelationValue?
    let agg: (RelationValue?, RelationValue) -> Result<RelationValue, RelationError>

    var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    /// Initialize a new aggregate relation.
    ///
    /// - parameter relation: The underlying relation that this is based on.
    /// - parameter attribute: The attribute of the relation which is used to obatin values.
    /// - parameter initial: The initial value to use when computing the aggregate. The
    ///                      aggregate of an empty relation is considered to have this value.
    ///                      If nil, the aggregate of an empty relation is also empty.
    /// - parameter agg: The aggregation function. It receives the current aggregate value as
    ///                  the first parameter, and the value in the current row as the second
    ///                  value. Its return value becomes the new aggregate value.
    init(relation: Relation, attribute: Attribute, initial: RelationValue?, agg: (RelationValue?, RelationValue) -> Result<RelationValue, RelationError>) {
        precondition(relation.scheme.attributes.contains(attribute))
        self.relation = relation
        self.attribute = attribute
        self.initialValue = initial
        self.agg = agg
    }
    
    /// A convenience initializer for aggregating functions which cannot fail and which always
    /// compare two values. If the initial value is nil, then the aggregate of an empty relation
    /// is empty, the aggregate of a relation containing a single row is the value stored in
    /// that row. The aggregate function is only called if there are two or more rows, and the
    /// first two call will pass in the values of the first two rows.
    convenience init(relation: Relation, attribute: Attribute, initial: RelationValue?, agg: (RelationValue, RelationValue) -> RelationValue) {
        self.init(relation: relation, attribute: attribute, initial: initial, agg: { (a, b) -> Result<RelationValue, RelationError> in
            if let a = a {
                return .Ok(agg(a, b))
            } else {
                return .Ok(b)
            }
        })
    }
    
    var scheme: Scheme {
        return [attribute]
    }
    
    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        let data = LogRelationIterationBegin(self)
        var done = false
        return LogRelationIterationReturn(data, AnyGenerator(body: {
            guard !done else { return nil }
            
            var soFar: RelationValue? = self.initialValue
            for row in self.relation.rows() {
                switch row {
                case .Ok(let row):
                    let newValue = row[self.attribute]
                    let aggregated = self.agg(soFar, newValue)
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
            return soFar.map({ .Ok(Row(values: [self.attribute: $0])) })
        }))
    }
    
    func contains(row: Row) -> Result<Bool, RelationError> {
        return .Ok(rows().contains({ $0.ok == row }))
    }
    
    func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        // TODO: Error, no-op, or pass through to underlying relation?
        return .Ok(())
    }
    
    func onAddFirstObserver() {
        relation.addWeakChangeObserver(self, method: self.dynamicType.observeChange)
    }
    
    private func observeChange(change: RelationChange) {
        // TODO: We're using the dumb and inefficient approach for now.  We should instead
        // cache the computed aggregate value and inspect the added/removed rows to determine
        // if the aggregate value has changed
        
        var preChangeRelation = relation
        if let added = change.added {
            preChangeRelation = preChangeRelation.difference(added)
        }
        if let removed = change.removed {
            preChangeRelation = preChangeRelation.union(removed)
        }
        let previousAgg = AggregateRelation(relation: preChangeRelation, attribute: self.attribute, initial: self.initialValue, agg: self.agg)

        let aggChange: RelationChange
        if self.intersection(previousAgg).isEmpty.ok == true {
            // The aggregate value has changed
            aggChange = RelationChange(added: self, removed: previousAgg)
        } else {
            // The aggregate value has not changed relative to the previous state
            aggChange = RelationChange()
        }
        notifyChangeObservers(aggChange)
    }
}

class CountRelation: Relation, RelationDefaultChangeObserverImplementation {
    let relation: Relation
    
    var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    init(relation: Relation) {
        self.relation = relation
    }
    
    var scheme: Scheme {
        return ["count"]
    }
    
    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        let data = LogRelationIterationBegin(self)
        var done = false
        return LogRelationIterationReturn(data, AnyGenerator(body: {
            guard !done else { return nil }
            done = true
            // TODO: Only include non-error rows?
            var count: Int64 = 0
            self.relation.rows().forEach({ _ in count += 1 })
            return .Ok(Row(values: ["count": RelationValue(count)]))
        }))
    }
    
    func contains(row: Row) -> Result<Bool, RelationError> {
        return .Ok(rows().contains({ $0.ok == row }))
    }
    
    func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        // TODO: Error, no-op, or pass through to underlying relation?
        return .Ok(())
    }
    
    func onAddFirstObserver() {
        relation.addWeakChangeObserver(self, method: self.dynamicType.observeChange)
    }
    
    private func observeChange(change: RelationChange) {
        // TODO: We're using the dumb and inefficient approach for now.  We should instead
        // cache the computed count and inspect the added/removed rows to determine
        // if the count has changed
        
        var preChangeRelation = relation
        if let added = change.added {
            preChangeRelation = preChangeRelation.difference(added)
        }
        if let removed = change.removed {
            preChangeRelation = preChangeRelation.union(removed)
        }
        let previousCount = CountRelation(relation: preChangeRelation)
        
        let countChange: RelationChange
        if self.intersection(previousCount).isEmpty.ok == true {
            // The count has changed
            countChange = RelationChange(added: self, removed: previousCount)
        } else {
            // The aggregate value has not changed relative to the previous state
            countChange = RelationChange()
        }
        notifyChangeObservers(countChange)
    }
}

class UniqueRelation: Relation, RelationDefaultChangeObserverImplementation {
    let relation: Relation
    let attribute: Attribute
    let matching: RelationValue
    
    var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    init(relation: Relation, attribute: Attribute, matching: RelationValue) {
        precondition(relation.scheme.attributes.contains(attribute))
        self.relation = relation
        self.attribute = attribute
        self.matching = matching
    }
    
    var scheme: Scheme {
        return relation.scheme
    }
    
    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        let data = LogRelationIterationBegin(self)
        var done = false
        var unique: Bool?
        let gen = relation.rows()
        return LogRelationIterationReturn(data, AnyGenerator(body: {
            guard !done else { return nil }
            if unique == nil {
                let projected = self.relation.project([self.attribute])
                let projectedRows = projected.rows()
                if let row = projectedRows.next() {
                    if projectedRows.next() != nil {
                        // There are two or more values
                        unique = false
                    } else {
                        // There is one unique value; see if it matches the expected value
                        unique = row.ok![self.attribute] == self.matching
                    }
                } else {
                    // There are no values
                    unique = false
                }
            }
            if unique == true {
                if let row = gen.next() {
                    return row
                } else {
                    done = true
                    return nil
                }
            } else {
                done = true
                return nil
            }
        }))
    }
    
    func contains(row: Row) -> Result<Bool, RelationError> {
        return .Ok(rows().contains({ $0.ok == row }))
    }
    
    func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        // TODO: Error, no-op, or pass through to underlying relation?
        return .Ok(())
    }
    
    func onAddFirstObserver() {
        relation.addWeakChangeObserver(self, method: self.dynamicType.observeChange)
    }
    
    private func observeChange(change: RelationChange) {
        // TODO
    }
}
