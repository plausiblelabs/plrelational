//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public struct ConcreteRelation: MutableRelation {
    public var scheme: Scheme
    public var values: Set<Row>
    
    var defaultSort: Attribute?
    
    public init(scheme: Scheme, values: Set<Row> = [], defaultSort: Attribute? = nil) {
        self.scheme = scheme
        self.values = values
        self.defaultSort = defaultSort
        LogRelationCreation(self)
    }
    
    public init(_ row: Row) {
        let scheme = Scheme(attributes: Set(row.attributes))
        self.init(scheme: scheme, values: [row])
    }
    
    public static func copyRelation(_ other: Relation) -> Result<ConcreteRelation, RelationError> {
        return mapOk(other.rows(), { $0 }).map({ ConcreteRelation(scheme: other.scheme, values: Set($0)) })
    }
    
    fileprivate func rowMatchesScheme(_ row: Row) -> Bool {
        return Set(row.attributes) == scheme.attributes
    }
    
    fileprivate func rowIsCompatible(_ row: Row) -> Bool {
        return Set(row.attributes).isSubset(of: scheme.attributes)
    }
    
    public func setDefaultSort(_ attribute: Attribute?) -> Relation {
        var new = self
        new.defaultSort = attribute
        return new
    }
    
    public func sortedValues(_ attribute: Attribute?) -> [Row] {
        if let attribute = attribute , scheme.attributes.contains(attribute) {
            return values.sorted(by: { $0[attribute].description.numericLessThan($1[attribute].description) })
        } else {
            return Array(values)
        }
    }
    
    public var contentProvider: RelationContentProvider {
        return .set({ self.values })
    }
    
    public mutating func add(_ row: Row) -> Result<Int64, RelationError> {
        precondition(rowMatchesScheme(row))
        values.insert(row)
        return .Ok(0)
    }
    
    public mutating func delete(_ rowToDelete: Row) {
        let toDelete = select(rowToDelete)
        values = Set(values.filter({
            // We know that the result of contains() can never fail here because it's ultimately our own implementation.
            toDelete.contains($0).ok! == false
        }))
    }
    
    public mutating func delete(_ query: SelectExpression) -> Result<Void, RelationError> {
        let toDelete = select(query)
        values = Set(values.filter({
            // We know that the result of contains() can never fail here because it's ultimately our own implementation.
            toDelete.contains($0).ok! == false
        }))
        return .Ok(())
    }
    
    public mutating func update(_ rowToFind: Row, newValues: Row) {
        let rowsToUpdate = select(rowToFind)
        delete(rowToFind)
        for rowToUpdate in rowsToUpdate.rows() {
            // We know that rows never fail, because this is ultimately our own implementation.
            var rowToAdd = rowToUpdate.ok!
            for (attribute, value) in newValues {
                rowToAdd[attribute] = value
            }
            self.add(rowToAdd)
        }
    }
    
    public mutating func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let rowsToUpdate = select(query)
        delete(query)
        for rowToUpdate in rowsToUpdate.rows() {
            // We know that rows never fail, because this is ultimately our own implementation.
            var rowToAdd = rowToUpdate.ok!
            for (attribute, value) in newValues {
                rowToAdd[attribute] = value
            }
            self.add(rowToAdd)
        }
        return .Ok()
    }
    
    public func contains(_ row: Row) -> Result<Bool, RelationError> {
        return .Ok(values.contains(row))
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
    
    public func addChangeObserver(_ observer: RelationObserver, kinds: [RelationObservationKind]) -> ((Void) -> Void) {
        //fatalError("Change observation isn't implemented for ConcreteRelation. Its implementation as a value type makes that weird. We might change that if we ever need it.")
        return { _ in }
    }
}

extension ConcreteRelation: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (Attribute, RelationValue)...) {
        scheme = Scheme(attributes: Set(elements.map({ $0.0 })))
        values = [Row(values: Dictionary(elements))]
    }
}

public func MakeRelation(_ attributes: [Attribute], _ rowValues: [RelationValue]...) -> ConcreteRelation {
    let scheme = Scheme(attributes: Set(attributes))
    let rows = rowValues.map({ values -> Row in
        precondition(values.count == attributes.count)
        return Row(values: Dictionary(zip(attributes, values)))
    })
    return ConcreteRelation(scheme: scheme, values: Set(rows), defaultSort: attributes.first)
}

extension ConcreteRelation: CustomStringConvertible, PlaygroundMonospace {
    public var description: String {
        let columns = scheme.attributes.sorted()
        let rows = sortedValues(defaultSort).map({ row -> [String] in
            return columns.map({ row[$0].description })
        })
        let all = ([columns.map({ $0.name })] + rows)
        let lengths = all.map({ $0.map({ $0.characters.count }) })
        let columnLengths = (0 ..< columns.count).map({ index in
            return lengths.map({ $0[index] }).reduce(0, Swift.max)
        })
        let padded = all.map({ zip(columnLengths, $0).map({ $1.pad(to: $0, with: " ") }) })
        let joined = padded.map({ $0.joined(separator: "  ") })
        return joined.joined(separator: "\n")
    }
}
