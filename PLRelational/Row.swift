//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public struct Row: Hashable, Sequence {
    var inlineRow: InlineRow
    
    private init(inlineRow: InlineRow) {
        self.inlineRow = inlineRow
    }
    
    public init<S: Sequence>(values: S) where S.Iterator.Element == (key: Attribute, value: RelationValue) {
        inlineRow = InlineRow.internSequence(values)
    }
    
    public static var empty = Row(values: [])
    
    public var hashValue: Int {
        return ObjectIdentifier(inlineRow).hashValue
    }
    
    public subscript(attribute: Attribute) -> RelationValue {
        get {
            return inlineRow[attribute] ?? .notFound
        }
        set {
            var d = Dictionary(inlineRow)
            d[attribute] = newValue
            inlineRow = InlineRow.internSequence(d)
        }
    }
    
    public func renameAttributes(_ renames: [Attribute: Attribute]) -> Row {
        if renames.isEmpty {
            return self
        } else {
            return Row(values: Dictionary(self.map({ attribute, value -> (Attribute, RelationValue) in
                let newAttribute = renames[attribute] ?? attribute
                return (newAttribute, value)
            })) )
        }
    }
    
    /// Create a new row containing only the values whose attributes are also in the attributes parameter.
    public func rowWithAttributes<Seq: Sequence>(_ attributes: Seq) -> Row where Seq.Iterator.Element == Attribute {
        return rowWithAttributes(Set(attributes))
    }
    
    /// Create a new row containing only the values whose attributes are also in the attributes parameter.
    public func rowWithAttributes(_ attributes: Set<Attribute>) -> Row {
        if attributes.isEmpty {
            return .empty
        } else if inlineRow.attributesEqual(attributes) {
            return self
        } else {
            return Row(inlineRow: inlineRow.rowWithAttributes(attributes))
        }
    }
    
    /// Produce a new Row by applying updated values to this Row. Any attributes that exist in `newValues`
    /// but not `self` will be added. Any attributes that exist in both will be set to the new value.
    /// Attributes only in `self` are left alone.
    public func rowWithUpdate(_ newValues: Row) -> Row {
        let updatedValues = self.map({
            (key: $0, value: newValues.inlineRow[$0] ?? $1)
        })
        return Row(values: updatedValues)
    }
    
    public struct Iterator: IteratorProtocol {
        var inner: InlineRow.Iterator
        
        public mutating func next() -> (Attribute, RelationValue)? {
            return inner.next()
        }
    }
    
    public func makeIterator() -> Iterator {
        return Iterator(inner: inlineRow.makeIterator())
    }
    
    public var attributes: LazyMapSequence<Row, Attribute> {
        return self.lazy.map({ $0.0 })
    }
    
    public var scheme: Scheme {
        return Scheme(attributes: Set(attributes))
    }
    
    public var count: Int {
        return inlineRow.count
    }
    
    public var isEmpty: Bool {
        return count == 0
    }
}

extension Row: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (Attribute, RelationValue)...) {
        self.init(values: elements.map({ (key: $0, value: $1) }))
    }
}

public func ==(a: Row, b: Row) -> Bool {
    return a.inlineRow === b.inlineRow
}

public func +(a: Row, b: Row) -> Row {
    return Row(values: Dictionary(a) + b)
}

extension Row: CustomStringConvertible {
    public var description: String {
        return Dictionary(inlineRow).description
    }
}

typealias InlineRowHeader = (count: Int, hash: Int)
typealias InlineRowElement = (Attribute, RelationValue)

final class InlineRow: ManagedBuffer<InlineRowHeader, InlineRowElement> {
    deinit {
        withUnsafeMutablePointers({ headerPtr, elementsPtr in
            _ = elementsPtr.deinitialize(count: headerPtr.pointee.count)
        })
    }
    
    var count: Int {
        return withUnsafeMutablePointers({
            return $0.0.pointee.count
        })
    }
    
    subscript(index: Int) -> (Attribute, RelationValue) {
        return withUnsafeMutablePointers({ headerPtr, elementPtr in
            let count = headerPtr.pointee.count
            precondition(index >= 0 && index < count)
            
            return elementPtr[index]
        })
    }
    
    subscript(attribute: Attribute) -> RelationValue? {
        for i in 0 ..< count {
            let (attr, value) = self[i]
            if attribute == attr {
                return value
            }
        }
        return nil
    }
    
    func attributeAtIndex(index: Int) -> Attribute {
        return withUnsafeMutablePointers({ headerPtr, elementPtr in
            let count = headerPtr.pointee.count
            precondition(index >= 0 && index < count)
            
            return elementPtr[index].0
        })
    }
    
    func attributesEqual(_ attributes: Set<Attribute>) -> Bool {
        let count = self.count
        if count != attributes.count { return false }
        
        for i in 0 ..< count {
            if !attributes.contains(attributeAtIndex(index: i)) {
                return false
            }
        }
        return true
    }
    
    func rowWithAttributes(_ attributes: Set<Attribute>) -> InlineRow {
        let row = InlineRow.create(capacity: attributes.count)
        self.withUnsafeMutablePointers({ myHeaderPtr, myElementsPtr in
            row.withUnsafeMutablePointers({ targetHeaderPtr, targetElementsPtr in
                for i in 0 ..< myHeaderPtr.pointee.count {
                    if attributes.contains(myElementsPtr[i].0) {
                        InlineRow.add(myElementsPtr[i], headerPtr: targetHeaderPtr, elementsPtr: targetElementsPtr)
                    }
                }
            })
        })
        return InlineRow.internRow(row)
    }
}

extension InlineRow: Sequence {
    struct Iterator: IteratorProtocol {
        var row: InlineRow
        var index: Int
        
        mutating func next() -> (Attribute, RelationValue)? {
            if index >= row.count {
                return nil
            } else {
                index += 1
                return row[index - 1]
            }
        }
    }
    
    func makeIterator() -> Iterator {
        return Iterator(row: self, index: 0)
    }
}

extension InlineRow {
    /// Create a new, empty InlineRow with enough capacity for the given number of pairs.
    ///
    /// - Parameter capacity: The maximum number of pairs the resulting object can store.
    /// - Returns: An empty InlineRow object with the given capacity. You may then call
    ///            add() up to that many times on the resulting object's pointers.
    static func create(capacity: Int) -> InlineRow {
        let obj = create(minimumCapacity: capacity, makingHeaderWith: { _ in (count: 0, hash: 5381) })
        return obj as! InlineRow
    }
    
    /// Add an Attribute/RelationValue pair to the given header/elements pointer. Pairs *must* be added in sorted order.
    /// The elements pointer *must* have sufficient storage allocated ahead of time to hold all pairs that will be added.
    /// This method does *not* reallocate any storage.
    ///
    /// - Parameters:
    ///   - pair: The pair to add.
    ///   - headerPtr: A pointer to the object's header.
    ///   - elementsPtr: A pointer to the object's elements.
    static func add(_ pair: (Attribute, RelationValue), headerPtr: UnsafeMutablePointer<InlineRowHeader>, elementsPtr: UnsafeMutablePointer<InlineRowElement>) {
        func combineHash(_ existing: inout Int, _ new: Int) {
            // DJB hash function, adapted from http://stackoverflow.com/questions/31438210/how-to-implement-the-hashable-protocol-in-swift-for-an-int-array-a-custom-strin
            existing = (existing << 5) &+ existing &+ new
        }
        
        (elementsPtr + headerPtr.pointee.count).initialize(to: pair)
        combineHash(&headerPtr.pointee.hash, pair.0.hashValue)
        combineHash(&headerPtr.pointee.hash, pair.1.hashValue)
        headerPtr.pointee.count += 1
    }
    
    /// Build a new InlineRow instance from the given sequence of Attribute/RelationValue pairs.
    ///
    /// - Parameter valuesSequence: The sequence of value pairs.
    /// - Returns: The new InlineRow object.
    static func buildFrom<S: Sequence>(_ valuesSequence: S) -> InlineRow where S.Iterator.Element == (key: Attribute, value: RelationValue) {
        let values = valuesSequence.sorted(by: { $0.key < $1.key })
        let count = values.count
        
        let obj = create(capacity: count)
        obj.withUnsafeMutablePointers({ headerPtr, elementsPtr in
            for i in 0 ..< count {
                add(values[i], headerPtr: headerPtr, elementsPtr: elementsPtr)
            }
        })
        return obj
    }
}

extension InlineRow: Hashable {
    static func ==(lhs: InlineRow, rhs: InlineRow) -> Bool {
        if lhs.count != rhs.count || lhs.hashValue != rhs.hashValue {
            return false
        }
        
        // Scan attributes and values separately, because checking attributes for equality should be much faster
        for i in 0 ..< lhs.count {
            let lhsAttr = lhs.attributeAtIndex(index: i)
            let rhsAttr = rhs.attributeAtIndex(index: i)
            if lhsAttr != rhsAttr {
                print("Collided hash: \(lhs.hashValue) \(rhs.hashValue)")
                return false
            }
        }
        
        for i in 0 ..< lhs.count {
            let lhsValue = lhs[i].1
            let rhsValue = rhs[i].1
            if lhsValue != rhsValue {
                print("Collided hash: \(lhs.hashValue) \(rhs.hashValue)")
                return false
            }
        }
        
        return true
    }
    
    var hashValue: Int {
        return withUnsafeMutablePointers({
            $0.0.pointee.hash
        })
    }
}

extension InlineRow: CustomDebugStringConvertible {
    var debugDescription: String {
        var result = ""
        
        withUnsafeMutablePointers({ headerPtr, elementsPtr in
            result.append(String(format: "<InlineRow %p count:%ld hash: %lx>", UInt(bitPattern: ObjectIdentifier(self)), headerPtr.pointee.count, headerPtr.pointee.hash))
            for i in 0 ..< headerPtr.pointee.count {
                let (attribute, value) = elementsPtr[i]
                result.append("\n    \(attribute): \(value)")
            }
        })
        
        return result
    }
}

extension InlineRow {
    static let extantRows = Mutexed<NSHashTable<AnyObject>>(NSHashTable(pointerFunctions: { () -> NSPointerFunctions in
        let pf = NSPointerFunctions(options: [.weakMemory])
        pf.hashFunction = { ptr, _ in unsafeBitCast(ptr, to: InlineRow.self).hashValue }
        pf.isEqualFunction = { a, b, _ in ObjCBool(unsafeBitCast(a, to: InlineRow.self) == unsafeBitCast(b, to: InlineRow.self)) }
        return pf
        }(), capacity: 0))
    
    
    static func internRow(_ row: InlineRow) -> InlineRow {
        return extantRows.withValue({
            if let extantRow = $0.member(row) {
                return extantRow as! InlineRow
            } else {
                $0.add(row)
                return row
            }
        })
    }
    
    static func internSequence<S: Sequence>(_ values: S) -> InlineRow where S.Iterator.Element == (key: Attribute, value: RelationValue) {
        return internRow(self.buildFrom(values))
    }
}

