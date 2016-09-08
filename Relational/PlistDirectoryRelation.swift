//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

import CommonCrypto


open class PlistDirectoryRelation: MutableRelation, RelationDefaultChangeObserverImplementation {
    open let scheme: Scheme
    
    open let primaryKey: Attribute
    
    let url: URL
    
    open var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    open static func withDirectory(_ url: URL, scheme: Scheme, primaryKey: Attribute, createIfDoesntExist: Bool) -> Result<PlistDirectoryRelation, RelationError> {
        do {
            if !(url as NSURL).checkResourceIsReachableAndReturnError(nil) {
                if createIfDoesntExist {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                } else {
                    return .Err(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: nil))
                }
            }
            
            return .Ok(PlistDirectoryRelation(scheme: scheme, primaryKey: primaryKey, url: url))
        } catch {
            return .Err(error)
        }
    }
    
    fileprivate init(scheme: Scheme, primaryKey: Attribute, url: URL) {
        precondition(scheme.attributes.contains(primaryKey), "Primary key must be in the scheme")
        self.scheme = scheme
        self.primaryKey = primaryKey
        self.url = url
    }
    
    open var contentProvider: RelationContentProvider {
        return .generator(self.rowGenerator)
    }
    
    open func contains(_ row: Row) -> Result<Bool, RelationError> {
        let keyValue = row[primaryKey]
        if case .notFound = keyValue {
            return .Ok(false)
        }
        
        let ourRow = readRow(primaryKey: keyValue)
        return ourRow.map({ $0 == row })
    }
    
    open func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
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
    
    open func add(_ row: Row) -> Result<Int64, RelationError> {
        return readRow(primaryKey: row[primaryKey]).then({ existingRow in
            if existingRow == row {
                return .Ok(0)
            }
            
            let removed = existingRow.map(ConcreteRelation.init)
            let added = ConcreteRelation(row)
            return writeRow(row).map({
                notifyChangeObservers(RelationChange(added: added, removed: removed), kind: .directChange)
                return 0
            })
        })
    }
    
    open func delete(_ query: SelectExpression) -> Result<Void, RelationError> {
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
    fileprivate static let fileExtension = "rowplist"
    fileprivate static let filePrefixLength = 2
    
    fileprivate func plistURL(forKeyValue value: RelationValue) -> URL {
        let valueData = canonicalData(for: value)
        let hash = SHA256(valueData)
        let hexHash = hexString(hash, uppercase: false)
        
        let prefix = hexHash.substring(to: hexHash.characters.index(hexHash.startIndex, offsetBy: PlistDirectoryRelation.filePrefixLength))
        
        return self.url
            .appendingPathComponent(prefix)
            .appendingPathComponent(hexHash)
            .appendingPathExtension(PlistDirectoryRelation.fileExtension)
    }
    
    fileprivate func canonicalData(for value: RelationValue) -> [UInt8] {
        switch value {
        case .null:
            return Array("n".utf8)
        case .integer(let value):
            return Array("i\(value)".utf8)
        case .real(let value):
            let swapped = CFConvertDoubleHostToSwapped(value)
            return Array("r\(swapped)".utf8)
        case .text(let string):
            let normalized = string.decomposedStringWithCanonicalMapping
            return Array("s\(normalized)".utf8)
        case .blob(let data):
            return "d".utf8 + data
            
        case .notFound:
            preconditionFailure("Can't get canonical data for .NotFound")
        }
    }
    
    fileprivate func readRow(url: URL) -> Result<Row, RelationError> {
        do {
            let data = try Data(contentsOf: url, options: [])
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            return Row.fromPlist(plist)
        } catch {
            return .Err(error)
        }
    }
    
    fileprivate func readRow(primaryKey key: RelationValue) -> Result<Row?, RelationError> {
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
    
    fileprivate func writeRow(_ row: Row) -> Result<Void, RelationError> {
        do {
            let primaryKeyValue = row[primaryKey]
            let url = plistURL(forKeyValue: primaryKeyValue)
            let directory = url.deletingLastPathComponent()
            
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            
            let plist = row.toPlist()
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: url, options: .atomicWrite)
            
            return .Ok()
        } catch {
            return .Err(error)
        }
    }
    
    fileprivate func deleteRow(primaryKey key: RelationValue) -> Result<Void, RelationError> {
        do {
            let url = plistURL(forKeyValue: key)
            try FileManager.default.removeItem(at: url)
            return .Ok()
        } catch {
            return .Err(error)
        }
    }
    
    fileprivate func rowURLs() -> AnyIterator<Result<URL, NSError>> {
        var enumerationError: NSError? = nil
        var returnedError = false
        let enumerator = FileManager.default.enumerator(at: self.url, includingPropertiesForKeys: nil, options: [], errorHandler: { url, error in
            enumerationError = error as NSError?
            return false
        })
        
        return AnyIterator({
            while true {
                if returnedError {
                    return nil
                }
                
                let url = enumerator?.nextObject()
                if let error = enumerationError {
                    returnedError = true
                    return .Err(error)
                } else if let url = url as? URL {
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
    
    fileprivate func rowGenerator() -> AnyIterator<Result<Row, RelationError>> {
        let urlGenerator = rowURLs()
        return AnyIterator({
            return urlGenerator.next().map({ urlResult in
                urlResult.mapErr({ $0 as RelationError }).then({
                    let result = self.readRow(url: $0)
                    return result
                })
            })
        })
    }
}
