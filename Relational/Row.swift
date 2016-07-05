//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public struct Row: Hashable {
    var internedRow: InternedRow
    
    public var values: [Attribute: RelationValue] {
        get {
            return internedRow.values
        }
        set {
            internedRow = InternedRow.intern(newValue)
        }
    }
    
    public init(values: [Attribute: RelationValue]) {
        internedRow = InternedRow.intern(values)
    }
    
    public var hashValue: Int {
        return ObjectIdentifier(internedRow).hashValue
    }
    
    public subscript(attribute: Attribute) -> RelationValue {
        get {
            return values[attribute] ?? .NotFound
        }
        set {
            values[attribute] = newValue
        }
    }
    
    public func renameAttributes(renames: [Attribute: Attribute]) -> Row {
        if renames.isEmpty {
            return self
        } else {
            return Row(values: Dictionary(values.map({ attribute, value in
                let newAttribute = renames[attribute] ?? attribute
                return (newAttribute, value)
            })))
        }
    }
    
    /// Create a new row containing only the values whose attributes are also in the attributes parameter.
    public func rowWithAttributes<Seq: SequenceType where Seq.Generator.Element == Attribute>(attributes: Seq) -> Row {
        return Row(values: Dictionary(attributes.flatMap({
            if let value = self.values[$0] {
                return ($0, value)
            } else {
                return nil
            }
        })))
    }
    
    /// Produce a new Row by applying updated values to this Row. Any attributes that exist in `newValues`
    /// but not `self` will be added. Any attributes that exist in both will be set to the new value.
    /// Attributes only in `self` are left alone.
    public func rowWithUpdate(newValues: Row) -> Row {
        let updatedValues = values + newValues.values
        return Row(values: updatedValues)
    }
}

extension Row: DictionaryLiteralConvertible {
    public init(dictionaryLiteral elements: (Attribute, RelationValue)...) {
        self.init(values: Dictionary(elements))
    }
}

public func ==(a: Row, b: Row) -> Bool {
    return a.internedRow === b.internedRow
}

extension Row: CustomStringConvertible {
    public var description: String {
        return internedRow.values.description
    }
}


class InternedRow: Hashable {
    let values: [Attribute: RelationValue]
    
    let hashValue: Int
    
    init(values: [Attribute: RelationValue]) {
        self.values = values
        
        // Note: needs to ensure the same value is produced regardless of order, so no fancy stuff.
        self.hashValue = values.map({ $0.0.hashValue ^ $0.1.hashValue }).reduce(0, combine: ^)
    }
}

func ==(a: InternedRow, b: InternedRow) -> Bool {
    return a.values == b.values
}

extension InternedRow {
    static let extantRows = Mutexed(NSHashTable(pointerFunctions: {
        let pf = NSPointerFunctions(options: [.WeakMemory])
        pf.hashFunction = { ptr, _ in unsafeBitCast(ptr, InternedRow.self).hashValue }
        pf.isEqualFunction = { a, b, _ in ObjCBool(unsafeBitCast(a, InternedRow.self) == unsafeBitCast(b, InternedRow.self)) }
        return pf
        }(), capacity: 0))
    
    
    static func intern(row: InternedRow) -> InternedRow {
        return extantRows.withValue({
            if let extantRow = $0.member(row) {
                return extantRow as! InternedRow
            } else {
                $0.addObject(row)
                return row
            }
        })
    }
    
    static func intern(values: [Attribute: RelationValue]) -> InternedRow {
        return intern(InternedRow(values: values))
    }
}
