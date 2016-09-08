//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public class PlistFileRelation: MutableRelation, RelationDefaultChangeObserverImplementation {
    public let scheme: Scheme
    
    var values: Set<Row>
    
    let url: NSURL
    
    public var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    private init(scheme: Scheme, url: NSURL) {
        self.scheme = scheme
        self.values = []
        self.url = url
    }
    
    public var contentProvider: RelationContentProvider {
        return .Set({ self.values })
    }
    
    public func contains(row: Row) -> Result<Bool, RelationError> {
        return .Ok(values.contains(row))
    }
    
    public func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let toUpdate = Set(values.filter({ query.valueWithRow($0).boolValue }))
        values.subtractInPlace(toUpdate)
        
        let updated = Set(toUpdate.map({ $0.rowWithUpdate(newValues) }))
        values.unionInPlace(updated)
        
        let added = ConcreteRelation(scheme: self.scheme, values: updated - toUpdate)
        let removed = ConcreteRelation(scheme: self.scheme, values: toUpdate - updated)
        
        notifyChangeObservers(RelationChange(added: added, removed: removed), kind: .DirectChange)
        
        return .Ok()
    }
    
    public func add(row: Row) -> Result<Int64, RelationError> {
        if !values.contains(row) {
            values.insert(row)
            notifyChangeObservers(RelationChange(added: ConcreteRelation(row), removed: nil), kind: .DirectChange)
        }
        return .Ok(0)
    }
    
    public func delete(query: SelectExpression) -> Result<Void, RelationError> {
        let toDelete = Set(values.lazy.filter({ query.valueWithRow($0).boolValue }))
        values.subtractInPlace(toDelete)
        notifyChangeObservers(RelationChange(added: nil, removed: ConcreteRelation(scheme: scheme, values: toDelete)), kind: .DirectChange)
        return .Ok()
    }
}

extension PlistFileRelation {
    enum Error: ErrorType {
        case UnknownTopLevelObject(unknownObject: AnyObject)
        case MissingValues
        case UnknownValuesObject(unknownObject: AnyObject)
    }
    
    public static func withFile(url: NSURL, scheme: Scheme, createIfDoesntExist: Bool) -> Result<PlistFileRelation, RelationError> {
        do {
            let data = try NSData(contentsOfURL: url, options: [])
            do {
                let plist = try NSPropertyListSerialization.propertyListWithData(data, options: [], format: nil)
                guard let dict = plist as? NSDictionary else { return .Err(Error.UnknownTopLevelObject(unknownObject: plist)) }
                
                guard let values = dict["values"] else { return .Err(Error.MissingValues) }
                guard let array = values as? NSArray else { return .Err(Error.UnknownValuesObject(unknownObject: values)) }
                
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
            let data = try NSPropertyListSerialization.dataWithPropertyList(dict, format: .XMLFormat_v1_0, options: 0)
            try data.writeToURL(url, options: .AtomicWrite)
            return .Ok()
        } catch {
            return .Err(error)
        }
    }
}
