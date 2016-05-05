struct UnionRelation: Relation {
    var a: Relation
    var b: Relation
    
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
    
    func addChangeObserver(f: Void -> Void) -> (Void -> Void) {
        let aRemove = a.addChangeObserver(f)
        let bRemove = b.addChangeObserver(f)
        return { aRemove(); bRemove() }
    }
}

struct IntersectionRelation: Relation {
    var a: Relation
    var b: Relation
    
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
    
    func addChangeObserver(f: Void -> Void) -> (Void -> Void) {
        let aRemove = a.addChangeObserver(f)
        let bRemove = b.addChangeObserver(f)
        return { aRemove(); bRemove() }
    }
}

struct DifferenceRelation: Relation {
    var a: Relation
    var b: Relation

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
    
    func addChangeObserver(f: Void -> Void) -> (Void -> Void) {
        let aRemove = a.addChangeObserver(f)
        let bRemove = b.addChangeObserver(f)
        return { aRemove(); bRemove() }
    }
}

struct ProjectRelation: Relation {
    var relation: Relation
    var scheme: Scheme
    
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
    
    func addChangeObserver(f: Void -> Void) -> (Void -> Void) {
        return relation.addChangeObserver(f)
    }
}

struct SelectRelation: Relation {
    var relation: Relation
    var terms: [ComparisonTerm]
    
    var scheme: Scheme {
        return relation.scheme
    }
    
    private func rowMatches(row: Row) -> Bool {
        return !terms.contains({ term in
            let lhs = term.lhs.valueForRow(row)
            let rhs = term.rhs.valueForRow(row)
            return !term.op.matches(lhs, rhs)
        })
    }
    
    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        let gen = relation.rows()
        return AnyGenerator(body: {
            while let row = gen.next() {
                switch row {
                case .Ok(let row):
                    if self.rowMatches(row) {
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
        return relation.contains(row).map({ $0 && rowMatches(row) })
    }
    
    func addChangeObserver(f: Void -> Void) -> (Void -> Void) {
        return relation.addChangeObserver(f)
    }
}

struct EquijoinRelation: Relation {
    var a: Relation
    var b: Relation
    var matching: [Attribute: Attribute]
    
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
    
    func addChangeObserver(f: Void -> Void) -> (Void -> Void) {
        let aRemove = a.addChangeObserver(f)
        let bRemove = b.addChangeObserver(f)
        return { aRemove(); bRemove() }
    }
}

struct RenameRelation: Relation {
    var relation: Relation
    var renames: [Attribute: Attribute]
    
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
    
    func addChangeObserver(f: Void -> Void) -> (Void -> Void) {
        return relation.addChangeObserver(f)
    }
}
