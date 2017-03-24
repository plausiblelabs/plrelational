//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


/// A set that can quickly look up elements based on the values of certain keys.
/// Initialize it with a set of primary keys. Later, elements holding a particular
/// value for a primary key can be looked up quickly.
public struct IndexedSet<Element: IndexableValue> {
    public let primaryKeys: Set<Element.Index>
    
    fileprivate var index: [Element.Index: [Element.Value: Set<Element>]]
    fileprivate var allValues: Set<Element>
}

extension IndexedSet {
    /// Initialize a set with the given primary keys. These keys will be indexed
    /// and elements with matching values for those keys can be quickly retrieved.
    public init<S: Sequence>(primaryKeys: S) where S.Iterator.Element == Element.Index {
        self.primaryKeys = Set(primaryKeys)
        index = .init(primaryKeys.map({ ($0, [:]) }))
        allValues = []
    }
    
    /// Retrieve all elements stored in the set.
    var values: Set<Element> {
        return allValues
    }
    
    /// Retrieve all elements in the set whose value for the given key matches.
    /// This is two dictionary lookups and thus very fast.
    /// The given key must be one of the primary keys used to initialize the set,
    /// otherwise the call will crash.
    /// If no elements have the given value for the given key, the empty set is returned.
    public func values(matchingKey: Element.Index, value: Element.Value) -> Set<Element> {
        return index[matchingKey]![value] ?? []
    }
    
    public mutating func add(element: Element) {
        allValues.insert(element)
        for indexKey in index.keys {
            add(indexedValue: element.value(index: indexKey), element: element, toDictionary: &index[indexKey]!)
        }
    }
    
    public mutating func remove(element: Element) {
        allValues.remove(element)
        for indexKey in index.keys {
            remove(indexedValue: element.value(index: indexKey), element: element, fromDictionary: &index[indexKey]!)
        }
    }
    
    public mutating func unionInPlace<S: Sequence>(_ elements: S) where S.Iterator.Element == Element {
        for element in elements {
            self.add(element: element)
        }
    }
    
    public mutating func subtractInPlace<S: Sequence>(_ elements: S) where S.Iterator.Element == Element {
        for element in elements {
            self.remove(element: element)
        }
    }
}

extension IndexedSet: Sequence {
    public func makeIterator() -> SetIterator<Element> {
        return allValues.makeIterator()
    }
}

extension IndexedSet {
    fileprivate mutating func add(indexedValue: Element.Value, element: Element, toDictionary: inout [Element.Value: Set<Element>]) {
        if toDictionary[indexedValue] == nil {
            toDictionary[indexedValue] = [element]
        } else {
            toDictionary[indexedValue]!.insert(element)
        }
    }
    
    fileprivate mutating func remove(indexedValue: Element.Value, element: Element, fromDictionary: inout [Element.Value: Set<Element>]) {
        _ = fromDictionary[indexedValue]?.remove(element)
    }
}

/// Protocol for values that can be stored in IndexedSet.
public protocol IndexableValue: Hashable {
    associatedtype Index: Hashable
    associatedtype Value: Hashable
    
    /// Return a value for a given index.
    func value(index: Index) -> Value
}

// Make Row an IndexableValue
extension Row: IndexableValue {
    public func value(index: Attribute) -> RelationValue {
        return self[index]
    }
}
