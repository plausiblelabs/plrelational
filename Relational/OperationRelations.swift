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
        let bUnique = b.rows().lazy.filter({ !($0.then({ self.a.contains($0) }).ok ?? true) })
        return AnyGenerator(a.rows().concat(bUnique.generate()))
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
            added: change.added.map({ $0.difference(otherRelation) }),
            removed: change.removed.map({ $0.difference(otherRelation) }))
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
        let aGen = a.rows()
        return AnyGenerator(body: {
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
        })
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
            added: change.added.map({ $0.intersection(otherRelation) }),
            removed: change.removed.map({ $0.intersection(otherRelation) }))
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
        let aGen = a.rows()
        return AnyGenerator(body: {
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
        })
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
        a.addWeakChangeObserver(self, method: self.dynamicType.notifyChangeObservers)
        b.addWeakChangeObserver(self, method: self.dynamicType.notifyChangeObservers)
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
        let gen = relation.rows()
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
    
    func contains(row: Row) -> Result<Bool, RelationError> {
        return relation.select(row).isEmpty.map(!)
    }
    
    func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        return relation.update(query, newValues: newValues)
    }
    
    func onAddFirstObserver() {
        relation.addWeakChangeObserver(self, method: self.dynamicType.notifyChangeObservers)
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
        let gen = relation.rows()
        return AnyGenerator(body: {
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
        })
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
        relation.addWeakChangeObserver(self, method: self.dynamicType.notifyChangeObservers)
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
        // TODO: try to figure out which of a and b is smaller, rather than just
        // arbitrarily picking an order.
        let first = b
        let second = a
        
        let firstAttributes = matching.values
        let secondAttributes = matching.keys
        let secondToFirstRenaming = matching
        
        // This maps join keys in `first` to entire rows in `first`.
        var firstKeyed: [Row: [Row]] = [:]
        for rowResult in first.rows() {
            guard let row = rowResult.ok else { return AnyGenerator(GeneratorOfOne(rowResult)) }
            let joinKey = row.rowWithAttributes(firstAttributes)
            if firstKeyed[joinKey] != nil {
                firstKeyed[joinKey]!.append(row)
            } else {
                firstKeyed[joinKey] = [row]
            }
        }
        
        let seq = second.rows().lazy.flatMap({ rowResult -> [Result<Row, RelationError>] in
            guard let row = rowResult.ok else { return [rowResult] }
            
            let joinKey = row.rowWithAttributes(secondAttributes).renameAttributes(secondToFirstRenaming)
            guard let bRows = firstKeyed[joinKey] else { return [] }
            return bRows.map({ .Ok(Row(values: $0.values + row.values)) })
        })
        return AnyGenerator(seq.generate())
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
        a.addWeakChangeObserver(self, method: self.dynamicType.notifyChangeObservers)
        b.addWeakChangeObserver(self, method: self.dynamicType.notifyChangeObservers)
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
        return AnyGenerator(
            relation
                .rows()
                .lazy
                .map({ $0.map({ $0.renameAttributes(self.renames) }) })
                .generate())
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
        relation.addWeakChangeObserver(self, method: self.dynamicType.notifyChangeObservers)
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
        return AnyGenerator(projected.rows().lazy.map({ (row: Result<Row, RelationError>) -> Result<Row, RelationError> in
            return row.map({ (row: Row) -> Row in
                return Row(values: row.values + self.newValues.values)
            })
        }).generate())
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
}
