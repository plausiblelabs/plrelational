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
    
    func onAddFirstObserver() {
        a.addWeakChangeObserver(self, method: self.dynamicType.notifyChangeObservers)
        b.addWeakChangeObserver(self, method: self.dynamicType.notifyChangeObservers)
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
        a.addWeakChangeObserver(self, method: self.dynamicType.notifyChangeObservers)
        b.addWeakChangeObserver(self, method: self.dynamicType.notifyChangeObservers)
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
        let aJustMatching = a.project(Scheme(attributes: Set(matching.keys)))
        let bJustMatching = b.project(Scheme(attributes: Set(matching.values)))
        let allCommon = aJustMatching.intersection(bJustMatching.renameAttributes(matching.reversed))
        
        let seq = allCommon.rows().lazy.flatMap({ row -> AnySequence<Result<Row, RelationError>> in
            switch row {
            case .Ok(let row):
                let renamedRow = row.renameAttributes(self.matching)
                let aMatching = self.a.select(row)
                let bMatching = self.b.select(renamedRow)
                
                return AnySequence(aMatching.rows().lazy.flatMap({ aRow -> AnySequence<Result<Row, RelationError>> in
                    return AnySequence(bMatching.rows().lazy.map({ bRow -> Result<Row, RelationError> in
                        return aRow.combine(bRow).map({ Row(values: $0.values + $1.values) })
                    }))
                }))
            case .Err:
                return AnySequence(CollectionOfOne(row))
            }
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
