//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public struct Row: Hashable, Sequence {
    var inlineRow: InlineRow
    
    public init<S: Sequence>(values: S) where S.Iterator.Element == (key: Attribute, value: RelationValue) {
        inlineRow = InlineRow.internSequence(values)
    }
    
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
        if inlineRow.attributesEqual(attributes) {
            return self
        } else {
            return Row(values: Dictionary(attributes.flatMap({
                if let value = inlineRow[$0] {
                    return ($0, value)
                } else {
                    return nil
                }
            })))
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


final class InlineRow: InlineMutableData {
    // Internal structure:
    //
    // Int: number of attribute/value pairs.
    // repeating:
    //    Int: absolute offset of attribute string beginning
    //    Int: absolute offset of value beginning
    // Followed by all serialized string/value data.
    
    var count: Int {
        return withUnsafeMutablePointerToElements({
            return UnsafeRawPointer($0).load(fromByteOffset: 0, as: Int.self)
        })
    }
    
    subscript(index: Int) -> (Attribute, RelationValue) {
        let count = self.count
        precondition(index >= 0 && index < count)
        
        return withUnsafeMutablePointers({ valuePtr, elementPtr in
            let raw = UnsafeRawPointer(elementPtr)
            let offsetIndex = index * 2 + 1
            let attributeOffset = raw.load(fromByteOffset: offsetIndex * MemoryLayout<Int>.size, as: Int.self)
            let valueOffset = raw.load(fromByteOffset: (offsetIndex + 1) * MemoryLayout<Int>.size, as: Int.self)
            let endOffset = (index < count - 1)
                ? raw.load(fromByteOffset: (offsetIndex + 2) * MemoryLayout<Int>.size, as: Int.self)
                : valuePtr.pointee.length
            
            let attribute = self.deserializeAttribute(elementPtr, start: attributeOffset, end: valueOffset)
            let value = self.deserializeValue(elementPtr, start: valueOffset, end: endOffset)
            return (attribute, value)
        })
    }
    
    subscript(attribute: Attribute) -> RelationValue? {
        return attribute.name.withCString({ attrPtr in
            let attrLen = Int(strlen(attrPtr))
            let count = self.count
            return withUnsafeMutablePointers({ valuePtr, elementPtr in
                elementPtr.withMemoryRebound(to: Int.self, capacity: count * 2 + 1, { header in
                    let count = header[0]
                    for i in 0 ..< count {
                        let headerOffset = i * 2 + 1
                        let attributeOffset = header[headerOffset]
                        let valueOffset = header[headerOffset + 1]
                        if attrLen == valueOffset - attributeOffset && memcmp(attrPtr, elementPtr + attributeOffset, attrLen) == 0 {
                            let endOffset = (i < count - 1) ? header[headerOffset + 2] : valuePtr.pointee.length
                            return self.deserializeValue(elementPtr, start: valueOffset, end: endOffset)
                        }
                    }
                    return nil
                })
            })
        })
    }
    
    func attributeAtIndex(index: Int) -> Attribute {
        let count = self.count
        precondition(index >= 0 && index < count)
        
        return withUnsafeMutablePointers({ valuePtr, elementPtr in
            let raw = UnsafeRawPointer(elementPtr)
            let offsetIndex = index * 2 + 1
            let attributeOffset = raw.load(fromByteOffset: offsetIndex * MemoryLayout<Int>.size, as: Int.self)
            let valueOffset = raw.load(fromByteOffset: (offsetIndex + 1) * MemoryLayout<Int>.size, as: Int.self)
            
            let attribute = self.deserializeAttribute(elementPtr, start: attributeOffset, end: valueOffset)
            return attribute
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
    static func buildFrom<S: Sequence>(_ valuesSequence: S) -> InlineRow where S.Iterator.Element == (key: Attribute, value: RelationValue) {
        let values = valuesSequence.sorted(by: { $0.key < $1.key })
        let estimatedSize = 100 // DO THIS BETTER
        
        var obj = self.make(estimatedSize)
        
        // Reserve space for the count and the offsets. Don't set their values yet, we'll do that at the end.
        obj = append(obj, pointer: nil, length: (1 + values.count * 2) * MemoryLayout<Int>.size)
        
        var offsets: [Int] = []
        offsets.reserveCapacity(values.count * 2)
        
        for (attribute, value) in values {
            offsets.append(serialize(&obj, attribute))
            offsets.append(serialize(&obj, value))
        }
        
        obj.withUnsafeMutablePointerToElements({ ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            raw.storeBytes(of: values.count, as: Int.self)
            memcpy(raw + MemoryLayout<Int>.size, offsets, offsets.count * MemoryLayout<Int>.size)
        })
        
        return obj
    }
    
    static func serialize(_ obj: inout InlineRow, _ string: String) -> Int {
        let offset = obj.length
        string.withCString({
            let len = Int(strlen($0))
            obj = append(obj, pointer: UnsafePointer($0), length: len)
        })
        return offset
    }
    
    static func serialize(_ obj: inout InlineRow, _ attribute: Attribute) -> Int {
        return serialize(&obj, attribute.name)
    }
    
    static func serialize(_ obj: inout InlineRow, _ value: RelationValue) -> Int {
        let offset = obj.length
        
        switch value {
        case .null:
            obj = append(obj, pointer: [0] as [UInt8], length: 1)
        case .integer(var value):
            obj = append(obj, pointer: [1] as [UInt8], length: 1)
            obj = append(obj, untypedPointer: &value, length: MemoryLayout.size(ofValue: value))
        case .real(var value):
            obj = append(obj, pointer: [2] as [UInt8], length: 1)
            obj = append(obj, untypedPointer: &value, length: MemoryLayout.size(ofValue: value))
        case .text(let string):
            obj = append(obj, pointer: [3] as [UInt8], length: 1)
            _ = serialize(&obj, string)
        case .blob(let data):
            obj = append(obj, pointer: [4] as [UInt8], length: 1)
            obj = append(obj, pointer: data, length: data.count)
        case .notFound:
            obj = append(obj, pointer: [5] as [UInt8], length: 1)
        }
        
        return offset
    }
}

extension InlineRow {
    func deserializeString(_ ptr: UnsafePointer<UInt8>, start: Int, end: Int) -> String {
        let buf = UnsafeBufferPointer(start: ptr + start, count: end - start)
        return String(bytes: buf, encoding: String.Encoding.utf8)!
    }
    
    func deserializeInternedString(_ ptr: UnsafePointer<UInt8>, start: Int, end: Int) -> InternedUTF8String {
        let data = InternedUTF8String.Data(ptr: ptr + start, length: end - start)
        return InternedUTF8String.get(data)
    }
    
    func deserializeAttribute(_ ptr: UnsafePointer<UInt8>, start: Int, end: Int) -> Attribute {
        return Attribute(deserializeInternedString(ptr, start: start, end: end))
    }
    
    func deserializeValue(_ ptr: UnsafePointer<UInt8>, start: Int, end: Int) -> RelationValue {
        switch ptr[start] {
        case 0:
            return .null
        case 1:
            return .integer(ptr.unalignedLoad(fromByteOffset: start + 1))
        case 2:
            return .real(ptr.unalignedLoad(fromByteOffset: start + 1))
        case 3:
            let value = deserializeString(ptr, start: start + 1, end: end)
            return .text(value)
        case 4:
            let buf = UnsafeBufferPointer(start: ptr + start + 1, count: end - start - 1)
            let value = Array(buf)
            return .blob(value)
        case 5:
            return .notFound
        default:
            fatalError("Unknown tag byte \(ptr[start])")
        }
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

