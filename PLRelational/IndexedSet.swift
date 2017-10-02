//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc: Implementation detail (will be made non-public eventually)
/// A set that can quickly look up elements based on the values of certain keys.
/// Initialize it with a set of primary keys. Later, elements holding a particular
/// value for a primary key can be looked up quickly.
///
/// NOTE: NOT a value type. It's too hard to make it a value type with the `MutableBox`
/// stuff going on. Once we can remove that, we can change this back to a struct.
public class IndexedSet<Element: IndexableValue> {
    public let primaryKeys: Set<Element.Index>
    
    // MutableBox is used here to allow for in-place mutation of the nested containers. Swift is currently
    // not smart enough to do that when the containers are placed directly in the Dictionary, which results
    // in atrocious performance. Boxing it in a class fixes that. Hopefully this will be fixed in some
    // future Swift version and then we can remove this.
    // Test case: https://gist.github.com/mikeash/a6ebc8cc4cb630c1893fd2909bb11d86
    fileprivate var index: [Element.Index: MutableBox<[Element.IndexedValue: MutableBox<Set<Element>>]>]
    public var allValues: Set<Element>

    /// Initialize a set with the given primary keys. These keys will be indexed
    /// and elements with matching values for those keys can be quickly retrieved.
    public init<S: Sequence>(primaryKeys: S) where S.Iterator.Element == Element.Index {
        self.primaryKeys = Set(primaryKeys)
        index = Dictionary(primaryKeys.map({ ($0, MutableBox([:])) }))
        allValues = []
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
extension IndexedSet {
    /// Retrieve all elements stored in the set.
    var values: Set<Element> {
        return allValues
    }
    
    /// Retrieve all elements in the set whose value for the given key matches.
    /// This is two dictionary lookups and thus very fast.
    /// The given key must be one of the primary keys used to initialize the set,
    /// otherwise the call will crash.
    /// If no elements have the given value for the given key, the empty set is returned.
    public func values(matchingKey: Element.Index, value: Element.IndexedValue) -> Set<Element> {
        return index[matchingKey]!.value[value]?.value ?? []
    }
    
    public func add(element: Element) {
        allValues.insert(element)
        for indexKey in index.keys {
            add(indexedValue: element.value(index: indexKey), element: element, toDictionary: &index[indexKey]!.value)
        }
    }
    
    public func remove(element: Element) {
        allValues.remove(element)
        for indexKey in index.keys {
            remove(indexedValue: element.value(index: indexKey), element: element, fromDictionary: &index[indexKey]!.value)
        }
    }
    
    public func unionInPlace<S: Sequence>(_ elements: S) where S.Iterator.Element == Element {
        for element in elements {
            self.add(element: element)
        }
    }
    
    public func subtractInPlace<S: Sequence>(_ elements: S) where S.Iterator.Element == Element {
        for element in elements {
            self.remove(element: element)
        }
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
extension IndexedSet: Sequence {
    public func makeIterator() -> SetIterator<Element> {
        return allValues.makeIterator()
    }
    
    public func contains(_ element: Element) -> Bool {
        return allValues.contains(element)
    }
}

extension IndexedSet {
    fileprivate func add(indexedValue: Element.IndexedValue, element: Element, toDictionary: inout [Element.IndexedValue: MutableBox<Set<Element>>]) {
        if let box = toDictionary[indexedValue] {
            box.value.insert(element)
        } else {
            toDictionary[indexedValue] = MutableBox([element])
        }
    }
    
    fileprivate func remove(indexedValue: Element.IndexedValue, element: Element, fromDictionary: inout [Element.IndexedValue: MutableBox<Set<Element>>]) {
        let box = fromDictionary[indexedValue]
        let removed = box?.value.remove(element)
        
        // If we removed the last value in the set, remove the entire set.
        // This keeps empty entries from building up over a long time.
        if removed != nil && box?.value.isEmpty == true {
            fromDictionary.removeValue(forKey: indexedValue)
        }
    }
}

/// These methods integrate with `SelectExpression` to efficiently pull out values based on
/// expressions that are suitable for it.
extension IndexedSet where Element == Row {
    /// Attempt to reduce a `SelectExpression` to a set of equality statements on our primary keys.
    /// On success, the return value is an array of attribute/value pairs, where the `SelectExpression`
    /// is equivalent to the logical OR of `attribute *== value` for each pair. If the `SelectExpression`
    /// cannot be reduced that way, then this method returns `nil`.
    func primaryKeyEquality(expression: SelectExpression) -> [(attribute: Attribute, value: RelationValue)]? {
        if case let op as SelectExpressionBinaryOperator = expression {
            switch op.op {
            case is EqualityComparator:
                if let attr = op.lhs as? Attribute, let value = op.rhs as? SelectExpressionConstantValue, primaryKeys.contains(attr) {
                    return [(attr, value.relationValue)]
                }
                if let attr = op.rhs as? Attribute, let value = op.lhs as? SelectExpressionConstantValue, primaryKeys.contains(attr) {
                    return [(attr, value.relationValue)]
                }
                
            case is OrComparator:
                if let lhsEquality = primaryKeyEquality(expression: op.lhs), let rhsEquality = primaryKeyEquality(expression: op.rhs) {
                    return lhsEquality + rhsEquality
                }
                
            default: break
            }
        }
        return nil
    }
    
    /// Attempt to efficiently fetch a set of values matching the given `SelectExpression`.
    /// If the values matching the `SelectExpression` can be computed efficiently, returns
    /// a set of matching values. Otherwise returns nil.
    func efficientValuesSet(expression: SelectExpression) -> Set<Row>? {
        // TODO: we probably also want to handle cases where the expression is
        // multiple primary key values ORed together.
        if expression as? Bool == false {
            return []
        } else if let equality = primaryKeyEquality(expression: expression) {
            var result = Set<Row>()
            for (attribute, value) in equality {
                result.formUnion(values(matchingKey: attribute, value: value))
            }
            return result
        } else {
            return nil
        }
    }
    
    /// Fetch the set of values matching the given `SelectExpression`. This is computed efficiently
    /// from the index if possible, and computed with a brute-force filter if not.
    func valuesMatching(expression: SelectExpression) -> Set<Row> {
        return efficientValuesSet(expression: expression)
            ?? values.filter({ expression.valueWithRow($0).boolValue })
    }
    
    /// A `RelationContentProvider` which will provide the contents of this set.
    var contentProvider: RelationContentProvider {
        return .efficientlySelectableGenerator({ expression in
            if expression.constantBoolValue == false {
                return AnyIterator([].makeIterator())
            } else if expression.constantBoolValue == true {
                return AnyIterator([.Ok(self.values)].makeIterator())
            } else if let rows = self.efficientValuesSet(expression: expression) {
                return AnyIterator([.Ok(rows)].makeIterator())
            } else {
                IndexedSet.logInefficientScan(self, expression)
                let filtered = self.values.filter({
                    expression.valueWithRow($0).boolValue
                })
                return AnyIterator(filtered.map({ .Ok([$0]) }).makeIterator())
            }
        }, approximateCount: {
            // TODO: efficientValuesSet may become less efficient for complex selects,
            // so we might want to change this then.
            return Double(self.efficientValuesSet(expression: $0)?.count ?? self.values.count)
        })
    }
    
    private static let logInefficientScans = false
    
    private static func logInefficientScan(_ r: IndexedSet, _ expression: SelectExpression) {
        guard logInefficientScans else { return }
        
        print("Inefficiently scanning \(r.values.count) rows for \(expression)")
        
        // Dummy call to efficientValuesSet so we can step into it in the debugger.
        _ = r.efficientValuesSet(expression: expression)
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
/// Protocol for values that can be stored in IndexedSet.
public protocol IndexableValue: Hashable {
    associatedtype Index: Hashable
    // Note: This has the "Indexed" prefix to avoid colliding with other associated types (e.g. Row wants to conform to both
    // ExpressibleByDictionaryLiteral and IndexableValue, but use a different "Value" type for each, and this would not
    // be possible if both are declared using the name "Value")
    associatedtype IndexedValue: Hashable
    
    /// Return a value for a given index.
    func value(index: Index) -> IndexedValue
}

/// :nodoc: Implementation detail (will be made non-public eventually)
// Make Row an IndexableValue
extension Row: IndexableValue {
    public func value(index: Attribute) -> RelationValue {
        return self[index]
    }
}
