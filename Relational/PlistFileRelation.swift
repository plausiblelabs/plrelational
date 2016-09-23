//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public class PlistFileRelation: PlistRelation, RelationDefaultChangeObserverImplementation {
    public let scheme: Scheme
    
    fileprivate var values: Set<Row>
    public internal(set) var url: URL?
    
    fileprivate let codec: DataCodec?
    
    public var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    fileprivate init(scheme: Scheme, url: URL?, codec: DataCodec?) {
        self.scheme = scheme
        self.values = []
        self.url = url
        self.codec = codec
    }
    
    public var contentProvider: RelationContentProvider {
        return .set({ self.values })
    }
    
    public func contains(_ row: Row) -> Result<Bool, RelationError> {
        return .Ok(values.contains(row))
    }
    
    public func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let toUpdate = Set(values.filter({ query.valueWithRow($0).boolValue }))
        values.subtract(toUpdate)
        
        let updated = Set(toUpdate.map({ $0.rowWithUpdate(newValues) }))
        values.formUnion(updated)
        
        let added = ConcreteRelation(scheme: self.scheme, values: updated - toUpdate)
        let removed = ConcreteRelation(scheme: self.scheme, values: toUpdate - updated)
        
        notifyChangeObservers(RelationChange(added: added, removed: removed), kind: .directChange)
        
        return .Ok()
    }
    
    public func add(_ row: Row) -> Result<Int64, RelationError> {
        if !values.contains(row) {
            values.insert(row)
            notifyChangeObservers(RelationChange(added: ConcreteRelation(row), removed: nil), kind: .directChange)
        }
        return .Ok(0)
    }
    
    public func delete(_ query: SelectExpression) -> Result<Void, RelationError> {
        let toDelete = Set(values.lazy.filter({ query.valueWithRow($0).boolValue }))
        values.subtract(toDelete)
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
    
    public static func withFile(_ url: URL?, scheme: Scheme, createIfDoesntExist: Bool, codec: DataCodec? = nil) -> Result<PlistFileRelation, RelationError> {
        if let url = url {
            // We have a URL, so we are either opening an existing relation or creating a new one at a specific location;
            if !createIfDoesntExist {
                // We are opening a relation, so let's require its existence at init time
                do {
                    let data = try Data(contentsOf: url, options: [])
                    let decodedData = codec?.decode(data) ?? data
                    let plist = try PropertyListSerialization.propertyList(from: decodedData, options: [], format: nil)
                    guard let dict = plist as? NSDictionary else { return .Err(Error.unknownTopLevelObject(unknownObject: plist)) }
                    
                    guard let values = dict["values"] else { return .Err(Error.missingValues) }
                    guard let array = values as? NSArray else { return .Err(Error.unknownValuesObject(unknownObject: values)) }
                    
                    let relationValueResults = array.map({ Row.fromPlist($0) })
                    let relationValuesResult = mapOk(relationValueResults, { $0 })
                    return relationValuesResult.map({
                        let r = PlistFileRelation(scheme: scheme, url: url, codec: codec)
                        r.values = Set($0)
                        return r
                    })
                } catch {
                    return .Err(error)
                }
            }
        } else {
            // We have no URL, so we are creating a new relation; we will defer file creation until the first save
            precondition(createIfDoesntExist)
        }
        return .Ok(PlistFileRelation(scheme: scheme, url: url, codec: codec))
    }
    
    public func save() -> Result<Void, RelationError> {
        guard let url = url else { fatalError("URL must be set prior to save") }
        
        let plistValues = values.map({ $0.toPlist() })
        let dict = ["values": plistValues]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            let encodedData = codec?.encode(data) ?? data
            try encodedData.write(to: url, options: .atomicWrite)
            return .Ok()
        } catch {
            return .Err(error)
        }
    }
}
