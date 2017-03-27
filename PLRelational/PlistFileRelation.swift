//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public class PlistFileRelation: PlistRelation, RelationDefaultChangeObserverImplementation {
    public let scheme: Scheme
    
    fileprivate var values: IndexedSet<Row>
    public internal(set) var url: URL?
    
    /// Whether the relation is transient (in which case, no changes are stored to disk).
    fileprivate let isTransient: Bool
    
    fileprivate let codec: DataCodec?
    
    public var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    fileprivate init(scheme: Scheme, primaryKeys: [Attribute], url: URL?, codec: DataCodec?, isTransient: Bool) {
        self.scheme = scheme
        self.values = IndexedSet(primaryKeys: primaryKeys)
        self.url = url
        self.isTransient = isTransient
        self.codec = codec
    }
    
    public var contentProvider: RelationContentProvider {
        return .efficientlySelectableGenerator({ expression in
            if let rows = self.efficientValuesSet(expression: expression) {
                return AnyIterator(rows.lazy.map({ .Ok($0) }).makeIterator())
            } else {
                let lazy = self.values.lazy
                let filtered = lazy.filter({
                    expression.valueWithRow($0).boolValue
                })
                return AnyIterator(filtered.map({ .Ok($0) }).makeIterator())
            }
        })
    }
    
    public func contains(_ row: Row) -> Result<Bool, RelationError> {
        return .Ok(values.contains(row))
    }
    
    public func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let toUpdate = self.valuesMatching(expression: query)
        values.subtractInPlace(toUpdate)
        
        let updated = Set(toUpdate.map({ $0.rowWithUpdate(newValues) }))
        values.unionInPlace(updated)
        
        let added = ConcreteRelation(scheme: self.scheme, values: updated - toUpdate)
        let removed = ConcreteRelation(scheme: self.scheme, values: toUpdate - updated)
        
        notifyChangeObservers(RelationChange(added: added, removed: removed), kind: .directChange)
        
        return .Ok()
    }
    
    public func add(_ row: Row) -> Result<Int64, RelationError> {
        if !values.contains(row) {
            values.add(element: row)
            notifyChangeObservers(RelationChange(added: ConcreteRelation(row), removed: nil), kind: .directChange)
        }
        return .Ok(0)
    }
    
    public func delete(_ query: SelectExpression) -> Result<Void, RelationError> {
        let toDelete = self.valuesMatching(expression: query)
        values.subtractInPlace(toDelete)
        notifyChangeObservers(RelationChange(added: nil, removed: ConcreteRelation(scheme: scheme, values: toDelete)), kind: .directChange)
        return .Ok()
    }
}

extension PlistFileRelation {
    enum Error: Swift.Error {
        case unknownTopLevelObject(unknownObject: Any)
        case missingValues
        case unknownValuesObject(unknownObject: Any)
    }
    
    public static func withFile(_ url: URL?, scheme: Scheme, primaryKeys: [Attribute], createIfDoesntExist: Bool, codec: DataCodec? = nil) -> Result<PlistFileRelation, RelationError> {
        if let url = url {
            // We have a URL, so we are either opening an existing relation or creating a new one at a specific location;
            if !createIfDoesntExist {
                // We are opening a relation, so let's require its existence at init time
                do {
                    let data = try Data(contentsOf: url, options: [])
                    let decodedDataResult = codec?.decode(data) ?? .Ok(data)
                    return try decodedDataResult.then({
                        let plist = try PropertyListSerialization.propertyList(from: $0, options: [], format: nil)
                        guard let dict = plist as? NSDictionary else { return .Err(Error.unknownTopLevelObject(unknownObject: plist)) }
                        
                        guard let values = dict["values"] else { return .Err(Error.missingValues) }
                        guard let array = values as? NSArray else { return .Err(Error.unknownValuesObject(unknownObject: values)) }
                        
                        let relationValueResults = array.map({ Row.fromPlist($0) })
                        let relationValuesResult = mapOk(relationValueResults, { $0 })
                        return relationValuesResult.map({
                            let r = PlistFileRelation(scheme: scheme, primaryKeys: primaryKeys, url: url, codec: codec, isTransient: false)
                            r.values.unionInPlace($0)
                            return r
                        })
                    })
                } catch {
                    return .Err(error)
                }
            }
        } else {
            // We have no URL, so we are creating a new relation; we will defer file creation until the first save
            precondition(createIfDoesntExist)
        }
        return .Ok(PlistFileRelation(scheme: scheme, primaryKeys: primaryKeys, url: url, codec: codec, isTransient: false))
    }
    
    /// Returns a new transient plist-backed relation (stored in memory only).
    public static func transient(scheme: Scheme, primaryKeys: [Attribute], codec: DataCodec? = nil) -> PlistFileRelation {
        return PlistFileRelation(scheme: scheme, primaryKeys: primaryKeys, url: nil, codec: codec, isTransient: true)
    }
    
    public func save() -> Result<Void, RelationError> {
        if isTransient {
            return .Ok(())
        }
        
        guard let url = url else { fatalError("URL must be set prior to save") }
        
        let plistValues = values.map({ $0.toPlist() })
        let dict = ["values": plistValues]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            let encodedDataResult = codec?.encode(data) ?? .Ok(data)
            return try encodedDataResult.map({ try $0.write(to: url, options: .atomicWrite) })
        } catch {
            return .Err(error)
        }
    }
}

private extension PlistFileRelation {
    func primaryKeyEquality(expression: SelectExpression) -> (Attribute, RelationValue)? {
        if case let op as SelectExpressionBinaryOperator = expression, op.op is EqualityComparator {
            if let attr = op.lhs as? Attribute, let value = op.rhs as? SelectExpressionConstantValue, values.primaryKeys.contains(attr) {
                return (attr, value.relationValue)
            }
            if let attr = op.rhs as? Attribute, let value = op.lhs as? SelectExpressionConstantValue, values.primaryKeys.contains(attr) {
                return (attr, value.relationValue)
            }
        }
        return nil
    }
    
    func efficientValuesSet(expression: SelectExpression) -> Set<Row>? {
        // TODO: we probably also want to handle cases where the expression is
        // multiple primary key values ORed together.
        if expression as? Bool == false {
            return []
        } else if let (attribute, value) = primaryKeyEquality(expression: expression) {
            return values.values(matchingKey: attribute, value: value)
        } else {
            return nil
        }
    }
    
    func valuesMatching(expression: SelectExpression) -> Set<Row> {
        return efficientValuesSet(expression: expression)
            ?? Set(values.filter({ expression.valueWithRow($0).boolValue }))
    }
}
