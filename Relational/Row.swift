//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public struct Row: Hashable {
    private var internedRow: InternedRow
    
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
        return unsafeBitCast(internedRow, Int.self)
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
        return Row(values: Dictionary(values.map({ attribute, value in
            let newAttribute = renames[attribute] ?? attribute
            return (newAttribute, value)
        })))
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
}

extension Row: DictionaryLiteralConvertible {
    public init(dictionaryLiteral elements: (Attribute, RelationValue)...) {
        self.init(values: Dictionary(elements))
    }
}

public func ==(a: Row, b: Row) -> Bool {
    return a.internedRow === b.internedRow
}


private class InternedRow {
    let values: [Attribute: RelationValue]
    
    init(values: [Attribute: RelationValue]) {
        self.values = values
    }
}

extension InternedRow: Hashable {
    var hashValue: Int {
        // Note: needs to ensure the same value is produced regardless of order, so no fancy stuff.
        return values.map({ $0.0.hashValue ^ $0.1.hashValue }).reduce(0, combine: ^)
    }
}

private func ==(a: InternedRow, b: InternedRow) -> Bool {
    return a.values == b.values
}

extension InternedRow {
    static var extantRows: Set<InternedRow> = []
    
    static func intern(row: InternedRow) -> InternedRow {
        if let index = extantRows.indexOf(row) {
            return extantRows[index]
        } else {
            extantRows.insert(row)
            return row
        }
    }
    
    static func intern(values: [Attribute: RelationValue]) -> InternedRow {
        return intern(InternedRow(values: values))
    }
}
