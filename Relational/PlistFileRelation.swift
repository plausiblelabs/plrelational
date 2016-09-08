//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


open class PlistFileRelation: MutableRelation, RelationDefaultChangeObserverImplementation {
    open let scheme: Scheme
    
    var values: Set<Row>
    
    let url: URL
    
    open var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    fileprivate init(scheme: Scheme, url: URL) {
        self.scheme = scheme
        self.values = []
        self.url = url
    }
    
    open var contentProvider: RelationContentProvider {
        return .set({ self.values })
    }
    
    open func contains(_ row: Row) -> Result<Bool, RelationError> {
        return .Ok(values.contains(row))
    }
    
    open func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let toUpdate = Set(values.filter({ query.valueWithRow($0).boolValue }))
        values.subtract(toUpdate)
        
        let updated = Set(toUpdate.map({ $0.rowWithUpdate(newValues) }))
        values.formUnion(updated)
        
        let added = ConcreteRelation(scheme: self.scheme, values: updated - toUpdate)
        let removed = ConcreteRelation(scheme: self.scheme, values: toUpdate - updated)
        
        notifyChangeObservers(RelationChange(added: added, removed: removed), kind: .directChange)
        
        return .Ok()
    }
    
    open func add(_ row: Row) -> Result<Int64, RelationError> {
        if !values.contains(row) {
            values.insert(row)
            notifyChangeObservers(RelationChange(added: ConcreteRelation(row), removed: nil), kind: .directChange)
        }
        return .Ok(0)
    }
    
    open func delete(_ query: SelectExpression) -> Result<Void, RelationError> {
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
    
    public static func withFile(_ url: URL, scheme: Scheme, createIfDoesntExist: Bool) -> Result<PlistFileRelation, RelationError> {
        do {
            let data = try Data(contentsOf: url, options: [])
            do {
                let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                guard let dict = plist as? NSDictionary else { return .Err(Error.unknownTopLevelObject(unknownObject: plist)) }
                
                guard let values = dict["values"] else { return .Err(Error.missingValues) }
                guard let array = values as? NSArray else { return .Err(Error.unknownValuesObject(unknownObject: values)) }
                
                let relationValueResults = array.map({ Row.fromPlist($0) })
                let relationValuesResult = mapOk(relationValueResults, { $0 })
                return relationValuesResult.map({
                    let r = PlistFileRelation(scheme: scheme, url: url)
                    r.values = Set($0)
                    return r
                })
            } catch {
                return .Err(error)
            }
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError && createIfDoesntExist {
            // NSData throws NSFileReadNoSuchFileError when the file doesn't exist. It doesn't seem to be documented
            // but given that it's an official Cocoa constant it seems safe enough.
            return .Ok(PlistFileRelation(scheme: scheme, url: url))
        } catch {
            return .Err(error)
        }
    }
    
    public func save() -> Result<Void, RelationError> {
        let plistValues = values.map({ $0.toPlist() })
        let dict = ["values": plistValues]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try data.write(to: url, options: .atomicWrite)
            return .Ok()
        } catch {
            return .Err(error)
        }
    }
}
