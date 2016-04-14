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
    
    func forEach(@noescape f: (Row, Void -> Void) -> Void) {
        var localStop = false
        a.forEach({ row, stop in f(row, { localStop = true; stop() }) })
        if !localStop {
            b.forEach({ row, stop in
                if !a.contains(row) {
                    f(row, stop)
                }
            })
        }
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
    
    func forEach(@noescape f: (Row, Void -> Void) -> Void) {
        a.forEach({ row, stop in
            if b.contains(row) {
                f(row, stop)
            }
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
    
    func forEach(@noescape f: (Row, Void -> Void) -> Void) {
        a.forEach({ row, stop in
            if !b.contains(row) {
                f(row, stop)
            }
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
    
    func forEach(@noescape f: (Row, Void -> Void) -> Void) {
        var seen: Set<Row> = []
        relation.forEach({ row, stop in
            let subvalues = scheme.attributes.map({ ($0, row[$0]) })
            let row = Row(values: Dictionary(subvalues))
            if !seen.contains(row) {
                seen.insert(row)
                f(row, stop)
            }
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
    
    func forEach(@noescape f: (Row, Void -> Void) -> Void) {
        relation.forEach({ row, stop in
            if rowMatches(row) {
                f(row, stop)
            }
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
    
    func forEach(@noescape f: (Row, Void -> Void) -> Void) {
        let aJustMatching = a.project(Scheme(attributes: Set(matching.keys)))
        let bJustMatching = b.project(Scheme(attributes: Set(matching.values)))
        let allCommon = aJustMatching.intersection(bJustMatching.renameAttributes(matching.reversed))
        
        allCommon.forEach({ row, allStop in
            let renamedRow = row.renameAttributes(matching)
            let aMatching = a.select(row)
            let bMatching = b.select(renamedRow)
            aMatching.forEach({ aRow, aStop in
                bMatching.forEach({ bRow, bStop in
                    let combinedRow = Row(values: aRow.values + bRow.values)
                    f(combinedRow, { aStop(); bStop(); allStop() })
                })
            })
        })
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
    
    func forEach(@noescape f: (Row, Void -> Void) -> Void) {
        relation.forEach({ row, stop in
            f(row.renameAttributes(renames), stop)
        })
    }
    
    func contains(row: Row) -> Bool {
        return relation.contains(row.renameAttributes(renames.reversed))
    }
}
