
public struct ConcreteRelation: Relation {
    public var scheme: Scheme
    public var values: Set<Row>
    
    var defaultSort: Attribute?
    
    private func rowMatchesScheme(row: Row) -> Bool {
        return Set(row.values.keys) == scheme.attributes
    }
    
    private func rowIsCompatible(row: Row) -> Bool {
        return Set(row.values.keys).isSubsetOf(scheme.attributes)
    }
    
    public func setDefaultSort(attribute: Attribute?) -> Relation {
        var new = self
        new.defaultSort = attribute
        return new
    }
    
    public func sortedValues(attribute: Attribute?) -> [Row] {
        if let attribute = attribute where scheme.attributes.contains(attribute) {
            return values.sort({ $0[attribute].description.numericLessThan($1[attribute].description) })
        } else {
            return Array(values)
        }
    }
    
    public mutating func add(row: Row) {
        precondition(rowMatchesScheme(row))
        values.insert(row)
    }
    
    public mutating func delete(rowToDelete: Row) {
        let toDelete = select(rowToDelete)
        values = Set(values.filter({ !toDelete.contains($0) }))
    }
    
    public mutating func change(rowToFind: Row, to: Row) {
        let rowsToUpdate = select(rowToFind)
        delete(rowToFind)
        for rowToUpdate in rowsToUpdate.rows() {
            var rowToAdd = rowToUpdate
            for (attribute, value) in to.values {
                rowToAdd[attribute] = value
            }
            self.add(rowToAdd)
        }
    }
    
    public func rows() -> AnyGenerator<Row> {
        return AnyGenerator(values.generate())
    }
    
    public func contains(row: Row) -> Bool {
        return values.contains(row)
    }
    
//    public func factor(attributes: [Attribute], link: Attribute) -> (Relation, Relation) {
//        var two = project(Scheme(attributes: Set(attributes)))
//        two.scheme.attributes.insert(link)
//        two.values = Set(two.values.enumerate().map({ (index, row) in
//            let newValues = row.values + [link: Value(index)]
//            return Row(values: newValues)
//        }))
//        
//        var one = self
//        one.scheme.attributes = scheme.attributes.subtract(Set(attributes)).union([link])
//        one.values = Set(one.values.map({ row in
//            let newValues = Dictionary(row.values.filter({ !attributes.contains($0.0) }))
//            let linkedValues = Dictionary(row.values.filter({ attributes.contains($0.0) }))
//            let linkedRow = two.select(Row(values: linkedValues)).values.first!
//            let linkValue = linkedRow[link]
//            
//            return Row(values: newValues + [link: linkValue])
//        }))
//        
//        return (one, two)
//    }
}

extension ConcreteRelation: DictionaryLiteralConvertible {
    public init(dictionaryLiteral elements: (Attribute, RelationValue)...) {
        scheme = Scheme(attributes: Set(elements.map({ $0.0 })))
        values = [Row(values: Dictionary(elements))]
    }
}

public func MakeRelation(attributes: [Attribute], _ rowValues: [RelationValue]...) -> ConcreteRelation {
    let scheme = Scheme(attributes: Set(attributes))
    let rows = rowValues.map({ values -> Row in
        precondition(values.count == attributes.count)
        return Row(values: Dictionary(zip(attributes, values)))
    })
    return ConcreteRelation(scheme: scheme, values: Set(rows), defaultSort: attributes.first)
}

extension ConcreteRelation: CustomStringConvertible, PlaygroundMonospace {
    public var description: String {
        let columns = scheme.attributes.sort()
        let rows = sortedValues(defaultSort).map({ row -> [String] in
            return columns.map({ row[$0].description })
        })
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
