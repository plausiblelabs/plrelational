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
    
    func rows() -> AnyGenerator<Row> {
        let bUnique = b.rows().lazy.filter({ !self.a.contains($0) })
        return AnyGenerator([a.rows(), AnyGenerator(bUnique.generate())].flatten().generate())
    }
    
    func contains(row: Row) -> Bool {
        return a.contains(row) || b.contains(row)
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
    
    func rows() -> AnyGenerator<Row> {
        let aGen = a.rows()
        return AnyGenerator(body: {
            while let row = aGen.next() {
                if self.b.contains(row) {
                    return row
                }
            }
            return nil
        })
    }
    
    func contains(row: Row) -> Bool {
        return a.contains(row) && b.contains(row)
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
    
    func rows() -> AnyGenerator<Row> {
        let aGen = a.rows()
        return AnyGenerator(body: {
            while let row = aGen.next() {
                if !self.b.contains(row) {
                    return row
                }
            }
            return nil
        })
    }
    
    func contains(row: Row) -> Bool {
        return a.contains(row) && !b.contains(row)
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
    
    func rows() -> AnyGenerator<Row> {
        let gen = relation.rows()
        var seen: Set<Row> = []
        return AnyGenerator(body: {
            while let row = gen.next() {
                let subvalues = self.scheme.attributes.map({ ($0, row[$0]) })
                let row = Row(values: Dictionary(subvalues))
                if !seen.contains(row) {
                    seen.insert(row)
                    return row
                }
            }
            return nil
        })
    }
    
    func contains(row: Row) -> Bool {
        return !relation.select(row).isEmpty
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
    
    func rows() -> AnyGenerator<Row> {
        let gen = relation.rows()
        return AnyGenerator(body: {
            while let row = gen.next() {
                if self.rowMatches(row) {
                    return row
                }
            }
            return nil
        })
    }
    
    func contains(row: Row) -> Bool {
        return relation.contains(row) && rowMatches(row)
    }
}

struct EquijoinRelation: Relation {
    var a: Relation
    var b: Relation
    var matching: [Attribute: Attribute]
    
    var scheme: Scheme {
        return Scheme(attributes: a.scheme.attributes.union(b.scheme.attributes))
    }

    func rows() -> AnyGenerator<Row> {
        let aJustMatching = a.project(Scheme(attributes: Set(matching.keys)))
        let bJustMatching = b.project(Scheme(attributes: Set(matching.values)))
        let allCommon = aJustMatching.intersection(bJustMatching.renameAttributes(matching.reversed))
        
        let seq = allCommon.rows().lazy.flatMap({ row -> AnySequence<Row> in
            let renamedRow = row.renameAttributes(self.matching)
            let aMatching = self.a.select(row)
            let bMatching = self.b.select(renamedRow)
            
            return AnySequence(aMatching.rows().lazy.flatMap({ aRow -> AnySequence<Row> in
                return AnySequence(bMatching.rows().lazy.map({ bRow -> Row in
                    return Row(values: aRow.values + bRow.values)
                }))
            }))
        })
        return AnyGenerator(seq.generate())
    }
    
    func contains(row: Row) -> Bool {
        return !self.select(row).isEmpty
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
    
    func rows() -> AnyGenerator<Row> {
        return AnyGenerator(
            relation
                .rows()
                .lazy
                .map({ $0.renameAttributes(self.renames) })
                .generate())
    }
    
    func contains(row: Row) -> Bool {
        return relation.contains(row.renameAttributes(renames.reversed))
    }
}
