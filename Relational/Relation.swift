
public protocol Relation: CustomStringConvertible, PlaygroundMonospace {
    var scheme: Scheme { get }
    
    func rows() -> AnyGenerator<Row>
    func contains(row: Row) -> Bool
    
    func forEach(@noescape f: (Row, Void -> Void) -> Void)
    
    func union(other: Relation) -> Relation
    func intersection(other: Relation) -> Relation
    func difference(other: Relation) -> Relation
    
    func join(other: Relation) -> Relation
    func equijoin(other: Relation, matching: [Attribute: Attribute]) -> Relation
    func thetajoin(other: Relation, terms: [ComparisonTerm]) -> Relation
    func split(terms: [ComparisonTerm]) -> (Relation, Relation)
    func divide(other: Relation) -> Relation
    
    func select(rowToFind: Row) -> Relation
    func select(terms: [ComparisonTerm]) -> Relation
    
    func renameAttributes(renames: [Attribute: Attribute]) -> Relation
}

extension Relation {
    public func forEach(@noescape f: (Row, Void -> Void) -> Void) {
        for row in rows() {
            var stop = false
            f(row, { stop = true })
            if stop { break }
        }
    }
    
    public func union(other: Relation) -> Relation {
        return UnionRelation(a: self, b: other)
    }
    
    public func intersection(other: Relation) -> Relation {
        return IntersectionRelation(a: self, b: other)
    }
    
    public func difference(other: Relation) -> Relation {
        return DifferenceRelation(a: self, b: other)
    }
    
    public func project(scheme: Scheme) -> Relation {
        return ProjectRelation(relation: self, scheme: scheme)
    }
    
    public func join(other: Relation) -> Relation {
        let intersectedScheme = Scheme(attributes: self.scheme.attributes.intersect(other.scheme.attributes))
        let matching = Dictionary(intersectedScheme.attributes.map({ ($0, $0) }))
        return equijoin(other, matching: matching)
    }
    
    public func equijoin(other: Relation, matching: [Attribute: Attribute]) -> Relation {
        return EquijoinRelation(a: self, b: other, matching: matching)
    }
    
    public func thetajoin(other: Relation, terms: [ComparisonTerm]) -> Relation {
        return self.join(other).select(terms)
    }
    
    public func split(terms: [ComparisonTerm]) -> (Relation, Relation) {
        let matching = select(terms)
        let notmatching = difference(matching)
        return (matching, notmatching)
    }
    
    public func divide(other: Relation) -> Relation {
        let resultingScheme = Scheme(attributes: self.scheme.attributes.subtract(other.scheme.attributes))
        let allCombinations = self.project(resultingScheme).join(other)
        let subtracted = allCombinations.difference(self)
        let projected = subtracted.project(resultingScheme)
        let result = self.project(resultingScheme).difference(projected)
        return result
    }
    
}

extension Relation {
    public func select(rowToFind: Row) -> Relation {
        let rowScheme = Set(rowToFind.values.map({ $0.0 }))
        precondition(rowScheme.isSubsetOf(scheme.attributes))
        let rowTerms = rowToFind.values.map({
            ComparisonTerm($0, EqualityComparator(), $1)
        })
        return select(rowTerms)
    }
    
    public func select(terms: [ComparisonTerm]) -> Relation {
        return SelectRelation(relation: self, terms: terms)
    }
}

extension Relation {
    public func renameAttributes(renames: [Attribute: Attribute]) -> Relation {
        return RenameRelation(relation: self, renames: renames)
    }
    
    public func renamePrime() -> Relation {
        let renames = Dictionary(scheme.attributes.map({ ($0, Attribute($0.name + "'")) }))
        return renameAttributes(renames)
    }
}

extension Relation {
    var isEmpty: Bool {
        return rows().next() == nil
    }
}

extension Relation {
    public var description: String {
        let columns = scheme.attributes.sort()
        let rows = self.rows().map({ row in columns.map({ row[$0].description }) })
        
        let all = ([columns.map({ $0.name })] + rows)
        let lengths = all.map({ $0.map({ $0.characters.count }) })
        let columnLengths = (0 ..< columns.count).map({ index in
            return lengths.map({ $0[index] }).reduce(0, combine: max)
        })
        let padded = all.map({ zip(columnLengths, $0).map({ $1.pad(to: $0, with: " ") }) })
        let joined = padded.map({ $0.joinWithSeparator("  ") })
        return joined.joinWithSeparator("\n")
    }
}
