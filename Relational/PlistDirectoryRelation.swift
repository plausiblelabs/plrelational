//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

import CommonCrypto


public class PlistDirectoryRelation: MutableRelation, RelationDefaultChangeObserverImplementation {
    public let scheme: Scheme
    
    public let primaryKey: Attribute
    
    let url: NSURL
    
    public var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    public static func withDirectory(url: NSURL, scheme: Scheme, primaryKey: Attribute, createIfDoesntExist: Bool) -> Result<PlistDirectoryRelation, RelationError> {
        do {
            if !url.checkResourceIsReachableAndReturnError(nil) {
                if createIfDoesntExist {
                    try NSFileManager.defaultManager().createDirectoryAtURL(url, withIntermediateDirectories: true, attributes: nil)
                } else {
                    return .Err(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: nil))
                }
            }
            
            return .Ok(PlistDirectoryRelation(scheme: scheme, primaryKey: primaryKey, url: url))
        } catch {
            return .Err(error)
        }
    }
    
    private init(scheme: Scheme, primaryKey: Attribute, url: NSURL) {
        precondition(scheme.attributes.contains(primaryKey), "Primary key must be in the scheme")
        self.scheme = scheme
        self.primaryKey = primaryKey
        self.url = url
    }
    
    public var contentProvider: RelationContentProvider {
        return .Generator(self.rowGenerator)
    }
    
    public func contains(row: Row) -> Result<Bool, RelationError> {
        let keyValue = row[primaryKey]
        if case .NotFound = keyValue {
            return .Ok(false)
        }
        
        let ourRow = readRow(primaryKey: keyValue)
        return ourRow.map({ $0 == row })
    }
    
    public func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        // TODO: for queries involving the primary key, be more efficient and don't scan everything.
        let toUpdate = flatmapOk(rowGenerator(), { query.valueWithRow($0).boolValue ? $0 : nil }).map(Set.init)
        let withUpdates = toUpdate.map({
            Set($0.map({
                $0.rowWithUpdate(newValues)
            }))
        })
        
        return toUpdate.combine(withUpdates).then({ toUpdate, withUpdates in
            let toUpdateKeys = Set(toUpdate.map({ $0[primaryKey] }))
            let withUpdatesKeys = Set(withUpdates.map({ $0[primaryKey] }))
            let toDeleteKeys = toUpdateKeys - withUpdatesKeys
            
            for updatedRow in withUpdates {
                let result = writeRow(updatedRow)
                if result.err != nil { return result }
            }
            for deleteKey in toDeleteKeys {
                let result = deleteRow(primaryKey: deleteKey)
                if result.err != nil { return result }
            }
            
            return .Ok()
        })
    }
    
    public func add(row: Row) -> Result<Int64, RelationError> {
        return readRow(primaryKey: row[primaryKey]).then({ existingRow in
            if existingRow == row {
                return .Ok(0)
            }
            
            let removed = existingRow.map(ConcreteRelation.init)
            let added = ConcreteRelation(row)
            return writeRow(row).map({
                notifyChangeObservers(RelationChange(added: added, removed: removed), kind: .DirectChange)
                return 0
            })
        })
    }
    
    public func delete(query: SelectExpression) -> Result<Void, RelationError> {
        // TODO: for queries involving the primary key, be more efficient and don't scan everything.
        let keysToDelete = flatmapOk(rowGenerator(), { query.valueWithRow($0).boolValue ? $0[primaryKey] : nil })
        return keysToDelete.then({
            for key in $0 {
                let result = deleteRow(primaryKey: key)
                if result.err != nil { return result }
            }
            return .Ok()
        })
    }
}

extension PlistDirectoryRelation {
    private static let fileExtension = "rowplist"
    private static let filePrefixLength = 2
    
    private func plistURL(forKeyValue value: RelationValue) -> NSURL {
        let valueData = canonicalData(for: value)
        let hash = SHA256(valueData)
        let hexHash = hexString(hash, uppercase: false)
        
        let prefix = hexHash.substringToIndex(hexHash.startIndex.advancedBy(PlistDirectoryRelation.filePrefixLength))
        
        return self.url
            .URLByAppendingPathComponent(prefix)
            .URLByAppendingPathComponent(hexHash)
            .URLByAppendingPathExtension(PlistDirectoryRelation.fileExtension)
    }
    
    private func canonicalData(for value: RelationValue) -> [UInt8] {
        switch value {
        case .NULL:
            return Array("n".utf8)
        case .Integer(let value):
            return Array("i\(value)".utf8)
        case .Real(let value):
            let swapped = CFConvertDoubleHostToSwapped(value)
            return Array("r\(swapped)".utf8)
        case .Text(let string):
            let normalized = string.decomposedStringWithCanonicalMapping
            return Array("s\(normalized)".utf8)
        case .Blob(let data):
            return "d".utf8 + data
            
        case .NotFound:
            preconditionFailure("Can't get canonical data for .NotFound")
        }
    }
    
    private func readRow(url url: NSURL) -> Result<Row, RelationError> {
        do {
            let data = try NSData(contentsOfURL: url, options: [])
            let plist = try NSPropertyListSerialization.propertyListWithData(data, options: [], format: nil)
            return Row.fromPlist(plist)
        } catch {
            return .Err(error)
        }
    }
    
    private func readRow(primaryKey key: RelationValue) -> Result<Row?, RelationError> {
        let url = plistURL(forKeyValue: key)
        let result = readRow(url: url)
        switch result {
        case .Ok(let row):
            return .Ok(row)
            
        case .Err(let error as NSError) where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError:
            // NSData throws NSFileReadNoSuchFileError when the file doesn't exist. It doesn't seem to be documented
            // but given that it's an official Cocoa constant it seems safe enough.
            return .Ok(nil)
            
        case .Err(let error):
            return .Err(error)
        }
    }
    
    private func writeRow(row: Row) -> Result<Void, RelationError> {
        do {
            let primaryKeyValue = row[primaryKey]
            let url = plistURL(forKeyValue: primaryKeyValue)
            let directory = url.URLByDeletingLastPathComponent!
            
            try NSFileManager.defaultManager().createDirectoryAtURL(directory, withIntermediateDirectories: true, attributes: nil)
            
            let plist = row.toPlist()
            let data = try NSPropertyListSerialization.dataWithPropertyList(plist, format: .XMLFormat_v1_0, options: 0)
            try data.writeToURL(url, options: .AtomicWrite)
            
            return .Ok()
        } catch {
            return .Err(error)
        }
    }
    
    private func deleteRow(primaryKey key: RelationValue) -> Result<Void, RelationError> {
        do {
            let url = plistURL(forKeyValue: key)
            try NSFileManager.defaultManager().removeItemAtURL(url)
            return .Ok()
        } catch {
            return .Err(error)
        }
    }
    
    private func rowURLs() -> AnyGenerator<Result<NSURL, NSError>> {
        var enumerationError: NSError? = nil
        var returnedError = false
        let enumerator = NSFileManager.defaultManager().enumeratorAtURL(self.url, includingPropertiesForKeys: nil, options: [], errorHandler: { url, error in
            enumerationError = error
            return false
        })
        
        return AnyGenerator(body: {
            while true {
                if returnedError {
                    return nil
                }
                
                let url = enumerator?.nextObject()
                if let error = enumerationError {
                    returnedError = true
                    return .Err(error)
                } else if let url = url as? NSURL {
                    switch url.isDirectory {
                    case .Ok(let isDirectory):
                        if !isDirectory && url.pathExtension == PlistDirectoryRelation.fileExtension {
                            return .Ok(url)
                        }
                    case .Err(let error):
                        return .Err(error)
                    }
                } else {
                    return nil
                }
            }
        })
    }
    
    private func rowGenerator() -> AnyGenerator<Result<Row, RelationError>> {
        let urlGenerator = rowURLs()
        return AnyGenerator(body: {
            return urlGenerator.next().map({ urlResult in
                urlResult.mapErr({ $0 as RelationError }).then({
                    let result = self.readRow(url: $0)
                    return result
                })
            })
        })
    }
}
