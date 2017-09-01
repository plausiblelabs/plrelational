//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

import CommonCrypto


private let logInefficientScans = false

private func logInefficientScan(_ r: PlistDirectoryRelation, _ expression: SelectExpression) {
    guard logInefficientScans else { return }
    
    print("Inefficiently scanning directory for \(expression)")
    
    // Dummy call to primaryKeyEquality so we can step into it in the debugger.
    _ = r.primaryKeyEquality(expression: expression)
}

public class PlistDirectoryRelation: PlistRelation, RelationDefaultChangeObserverImplementation {
    public let scheme: Scheme
    public let primaryKey: Attribute
    
    public internal(set) var url: URL?
    
    fileprivate let codec: DataCodec?
    
    public var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    public var debugName: String?
    
    public let saveObservers = RemovableSet<(URL) -> Void>()
    
    fileprivate var writeCache = WriteCache()
    fileprivate var readCache = ReadCache()
    
    /// Create a new relation with a given directory.
    ///
    /// - Parameters:
    ///   - url: The URL to the directory to use. If nil, the relation is held in memory
    ///          and the `url` property must be set before calling save().
    ///   - scheme: The relation scheme.
    ///   - primaryKey: The primary key to use for the relation. A row's value for the primary
    ///                 key is used to derive the filename it's stored under. Joins/selects
    ///                 that use the primary key will avoid scanning the entire directory.
    ///   - create: If false, then a URL must be provided and an accessible directory must exist
    ///             in that location. If no URL is provided, that is a precondition failure. If the
    ///             URL is provided but no directory exists there or isn't accessible, an error
    ///             is returned. If `create` is true, then the directory can be nonexistent and
    ///             the url can be nil. If the directory does exist, then its contents will be
    ///             returned as part of the relation's contents. Existing data is not deleted
    ///             just because `create: true`.
    ///   - codec: A DataCodec used to encode and decode individual Row plists on disk.
    /// - Returns: The newly created directory relation, or an error if creation failed.
    public static func withDirectory(_ url: URL?, scheme: Scheme, primaryKey: Attribute, create: Bool, codec: DataCodec? = nil) -> Result<PlistDirectoryRelation, RelationError> {
        if let url = url {
            // We have a URL, so we are either opening an existing relation or creating a new one at a specific location
            if !create {
                // We are opening a relation, so let's require its existence at init time
                if !(url as NSURL).checkResourceIsReachableAndReturnError(nil) {
                    return .Err(NSError.fileNotFound)
                }
            }
        } else {
            // We have no URL, so we are creating a new relation; we will defer file creation until the first write
            precondition(create)
        }
        return .Ok(PlistDirectoryRelation(scheme: scheme, primaryKey: primaryKey, url: url, codec: codec))
    }
    
    fileprivate init(scheme: Scheme, primaryKey: Attribute, url: URL?, codec: DataCodec?) {
        precondition(scheme.attributes.contains(primaryKey), "Primary key must be in the scheme")
        self.scheme = scheme
        self.primaryKey = primaryKey
        self.url = url
        self.codec = codec
    }
    
    public var contentProvider: RelationContentProvider {
        return .efficientlySelectableGenerator({ expression in
            if expression.constantBoolValue == false {
                return AnyIterator([].makeIterator())
            } else if let value = self.primaryKeyEquality(expression: expression) {
                // TODO: we probably also want to handle cases where the expression is
                // multiple primary key values ORed together.
                return self.filteredRowGenerator(primaryKeyValues: [value])
            } else {
                logInefficientScan(self, expression)
                let lazy = self.rowGenerator().lazy
                let filtered = lazy.filter({
                    $0.ok.map({
                        expression.valueWithRow($0).boolValue
                    }) ?? true
                })
                return AnyIterator(filtered.map({ $0.map({ [$0] }) }).makeIterator())
            }
        }, approximateCount: {
            if self.primaryKeyEquality(expression: $0) != nil {
                return 1.0
            } else {
                return nil
            }
        })
    }
    
    fileprivate func primaryKeyEquality(expression: SelectExpression) -> RelationValue? {
        if case let op as SelectExpressionBinaryOperator = expression, op.op is EqualityComparator {
            if op.lhs as? Attribute == primaryKey, let value = op.rhs as? SelectExpressionConstantValue {
                return value.relationValue
            }
            if op.rhs as? Attribute == primaryKey, let value = op.lhs as? SelectExpressionConstantValue {
                return value.relationValue
            }
        }
        return nil
    }
    
    public func contains(_ row: Row) -> Result<Bool, RelationError> {
        let keyValue = row[primaryKey]
        if case .notFound = keyValue {
            return .Ok(false)
        }
        
        let ourRow = readRow(primaryKey: keyValue)
        return ourRow.map({ $0 == row })
    }
    
    public func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
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
                let url = plistURL(forRow: updatedRow)
                let key = updatedRow[primaryKey]
                if let url = url {
                    readCache.clear(url: url)
                }
                writeCache.add(url: url, key: key, row: updatedRow)
            }
            for deleteKey in toDeleteKeys {
                let url = plistURL(forKeyValue: deleteKey)
                if let url = url {
                    readCache.clear(url: url)
                }
                writeCache.delete(url: url, key: deleteKey)
            }
            
            let added = ConcreteRelation(scheme: self.scheme, values: withUpdates - toUpdate)
            let removed = ConcreteRelation(scheme: self.scheme, values: toUpdate - withUpdates)
            notifyChangeObservers(RelationChange(added: added, removed: removed), kind: .directChange)
            
            return .Ok()
        })
    }
    
    public func add(_ row: Row) -> Result<Int64, RelationError> {
        return readRow(primaryKey: row[primaryKey]).then({ existingRow in
            if existingRow == row {
                return .Ok(0)
            }
            
            let removed = existingRow.map(ConcreteRelation.init)
            let added = ConcreteRelation(row)
            let url = plistURL(forRow: row)
            let key = row[primaryKey]
            writeCache.add(url: url, key: key, row: row)
            notifyChangeObservers(RelationChange(added: added, removed: removed), kind: .directChange)
            
            return .Ok(0)
        })
    }
    
    public func delete(_ query: SelectExpression) -> Result<Void, RelationError> {
        // TODO: for queries involving the primary key, be more efficient and don't scan everything.
        let keysToDelete = flatmapOk(rowGenerator(), { query.valueWithRow($0).boolValue ? $0[primaryKey] : nil })
        
        return keysToDelete.then({
            for key in $0 {
                let url = plistURL(forKeyValue: key)
                writeCache.delete(url: url, key: key)
            }
            return .Ok()
        })
    }
    
    public func save() -> Result<Void, RelationError> {
        // XXX: If there were no writes to this relation in the transaction, and the directory didn't already
        // exist, then we want to create it now, otherwise the relation won't open successfully next time around
        // due to the strict checks we have in `withDirectory` at the moment
        if !(url! as NSURL).checkResourceIsReachableAndReturnError(nil) {
            do {
                try FileManager.default.createDirectory(at: url!, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return .Err(error)
            }
        }
        
        for (urlOrKey, row) in writeCache.toWrite {
            if case .key = urlOrKey {
                // Only write out entries with keys, entries with URLs will be duplicates and may not exist.
                let result = writeRow(row)
                if result.err != nil {
                    return result
                }
            }
            // Don't delete anything we're writing or overwriting.
            writeCache.toDelete.remove(urlOrKey)
        }
        
        for url in writeCache.toDelete.lazy.flatMap({ $0.urlValue }) {
            do {
                try FileManager.default.removeItem(at: url)
                for observer in saveObservers {
                    observer(url)
                }
            } catch {
                // Ignore file not found, since we may legitimately try to delete files that don't exist
                if !error.isFileNotFound {
                    return .Err(error)
                }
            }
        }
        
        writeCache = WriteCache()

        return .Ok(())
    }
}

extension PlistDirectoryRelation {
    fileprivate static let fileExtension = "rowplist"
    fileprivate static let filePrefixLength = 2
    
    fileprivate func plistURL(forKeyValue value: RelationValue) -> URL? {
        guard let baseURL = self.url else { return nil }
        
        let valueData = canonicalData(for: value)
        let hash = SHA256(valueData)
        let hexHash = hexString(hash, uppercase: false)
        
        let prefix = hexHash.substring(to: hexHash.characters.index(hexHash.startIndex, offsetBy: PlistDirectoryRelation.filePrefixLength))
        
        return baseURL
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(hexHash, isDirectory: false)
            .appendingPathExtension(PlistDirectoryRelation.fileExtension)
    }
    
    fileprivate func plistURL(forRow row: Row) -> URL? {
        return plistURL(forKeyValue: row[primaryKey])
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
            if let row = writeCache.toWrite[.url(url)] {
                return .Ok(row)
            }
            
            if writeCache.toDelete.contains(.url(url)) {
                return .Err(NSError.fileNotFound)
            }
            
            let modDate = flatten(try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            if let entry = readCache[url] {
                if modDate == entry.date {
                    return .Ok(entry.row)
                }
            }
            
            let data = try Data(contentsOf: url, options: [])
            let decodedDataResult = codec?.decode(data) ?? .Ok(data)
            return try decodedDataResult.then({
                let plist = try PropertyListSerialization.propertyList(from: $0, options: [], format: nil)
                let row = Row.fromPlist(plist).then({
                    return $0.scheme == self.scheme
                        ? .Ok($0)
                        : .Err(Error.schemeMismatch(foundScheme: $0.scheme))
                })
                if let modDate = modDate, let row = row.ok {
                    readCache[url] = (modDate, row)
                }
                return row
            })
        } catch {
            return .Err(error)
        }
    }
    
    fileprivate func readRow(primaryKey key: RelationValue) -> Result<Row?, RelationError> {
        if self.url == nil {
            // Return no row for the case where a directory URL hasn't yet been set
            return .Ok(nil)
        }
        
        guard let url = plistURL(forKeyValue: key) else { return .Ok(nil) }
        let result = readRow(url: url)
        switch result {
        case .Ok(let row):
            return .Ok(row)
            
        case .Err(let error) where error.isFileNotFound:
            return .Ok(nil)
            
        case .Err(let error):
            return .Err(error)
        }
    }
    
    fileprivate func writeRow(_ row: Row) -> Result<Void, RelationError> {
        do {
            let url = plistURL(forRow: row)!
            let directory = url.deletingLastPathComponent()
            
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            
            let plist = row.toPlist()
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            let encodedDataResult = codec?.encode(data) ?? .Ok(data)
            return try encodedDataResult.map({
                try $0.write(to: url, options: .atomicWrite)
                for observer in saveObservers {
                    observer(url)
                }
            })
        } catch {
            return .Err(error)
        }
    }
    
    fileprivate func rowURLs() -> AnyIterator<Result<URL, NSError>> {
        // This should never be called in the first place if url is nil. That case is handled
        // in the caller.
        precondition(url != nil)
        
        // XXX: enumerator(at:url) seems to crash if the directory does not exist, so let's avoid that; we need to find
        // a better solution that doesn't require constantly checking for its existence
        if let url = url {
            if !(url as NSURL).checkResourceIsReachableAndReturnError(nil) {
                // If the directory doesn't even exist, then just return URLs in the write cache.
                return AnyIterator(writeCache.toWrite.keys.lazy.flatMap({ $0.urlValue }).map(Result.Ok).makeIterator())
            }
        }
        
        var enumerationError: NSError? = nil
        var returnedError = false
        let enumerator = FileManager.default.enumerator(at: self.url!, includingPropertiesForKeys: nil, options: [], errorHandler: { url, error in
            enumerationError = error as NSError?
            return false
        })
        
        var writeCacheURLIterator: Optional = writeCache.toWrite.keys.lazy.flatMap({ $0.urlValue }).makeIterator()
        let writeCacheDeleted = writeCache.toDelete
        
        return AnyIterator({
            if let writeCacheURL = writeCacheURLIterator?.next() {
                return .Ok(writeCacheURL)
            } else {
                writeCacheURLIterator = nil
            }
            
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
                        if !isDirectory &&
                            url.pathExtension == PlistDirectoryRelation.fileExtension &&
                            !writeCacheDeleted.contains(.url(url)) {
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
        if url != nil {
            let urlGenerator = rowURLs()
            return AnyIterator({
                return urlGenerator.next().map({ urlResult in
                    urlResult.mapErr({ $0 as RelationError }).then({
                        return self.readRow(url: $0)
                    })
                })
            })
        } else {
            return AnyIterator(writeCache.toWrite.values.lazy.map(Result.Ok).makeIterator())
        }
    }
    
    fileprivate func filteredRowGenerator(primaryKeyValues: [RelationValue]) -> AnyIterator<Result<Set<Row>, RelationError>> {
        let rows = primaryKeyValues.lazy.flatMap({ value -> Result<Set<Row>, RelationError>? in
            let result = self.readRow(primaryKey: value)
            switch result {
            case .Ok(nil):
                return nil
            case .Ok(.some(let row)):
                return .Ok([row])
            case .Err(let err):
                return .Err(err)
            }
        })
        return AnyIterator(rows.makeIterator())
    }
}

extension PlistDirectoryRelation {
    fileprivate struct WriteCache {
        enum URLOrKey: Hashable {
            case standardizedURL(URL)
            case key(RelationValue)
            
            var hashValue: Int {
                switch self {
                case .standardizedURL(let url): return url.hashValue
                case .key(let value): return ~value.hashValue
                }
            }
            
            static func url(_ url: URL) -> URLOrKey {
                return .standardizedURL(url.standardizedFileURL)
            }
            
            var urlValue: URL? {
                switch self {
                case .standardizedURL(let url): return url
                case .key: return nil
                }
            }
            
            static func ==(lhs: URLOrKey, rhs: URLOrKey) -> Bool {
                switch (lhs, rhs) {
                case let (.standardizedURL(lhs), .standardizedURL(rhs)): return lhs == rhs
                case let (.key(lhs), .key(rhs)): return lhs == rhs
                default: return false
                }
            }
        }
        
        var toWrite: [URLOrKey: Row] = [:]
        var toDelete: Set<URLOrKey> = []
        
        mutating func add(url: URL?, key: RelationValue, row: Row) {
            if let url = url {
                toWrite[.url(url)] = row
                toDelete.remove(.url(url))
            }
            
            toWrite[.key(key)] = row
            toDelete.remove(.key(key))
        }
        
        mutating func delete(url: URL?, key: RelationValue) {
            if let url = url {
                toWrite.removeValue(forKey: .url(url))
                toDelete.insert(.url(url))
            }
            
            toWrite.removeValue(forKey: .key(key))
            toDelete.insert(.key(key))
        }
        
        mutating func clear(url: URL) {
            toWrite.removeValue(forKey: .url(url))
            toDelete.remove(.url(url))
        }
    }
}

extension PlistDirectoryRelation {
    fileprivate struct ReadCache {
        typealias Entry = (date: Date, row: Row)
        
        let cache = NSCache<NSURL, AnyObject>()
        
        subscript(url: URL) -> Entry? {
            get {
                return cache.object(forKey: standardized(url: url)) as? Entry
            }
            set {
                if let newValue = newValue {
                    cache.setObject(newValue as AnyObject, forKey: standardized(url: url))
                } else {
                    cache.removeObject(forKey: standardized(url: url))
                }
            }
        }
        
        private func standardized(url: URL) -> NSURL {
            return url.standardizedFileURL as NSURL
        }
        
        func clear(url: URL) {
            cache.removeObject(forKey: standardized(url: url))
        }
    }
}

extension PlistDirectoryRelation {
    public enum Error: Swift.Error {
        case schemeMismatch(foundScheme: Scheme)
    }
}

extension PlistDirectoryRelation {
    public func replaceLocalFile(url: URL, movingURL: URL) -> Result<Bool, Swift.Error> {
        if urlMatches(url) {
            let existingRow = readRow(url: url)
            let newRow = readRow(url: movingURL)
            readCache.clear(url: movingURL)
            
            return newRow.then({ newRow in
                do {
                    _ = try FileManager.default.replaceItemAt(url, withItemAt: movingURL)
                    
                    writeCache.clear(url: url)
                    readCache.clear(url: url)
                    if existingRow.ok != newRow {
                        let added = ConcreteRelation(newRow)
                        let removed = existingRow.ok.map(ConcreteRelation.init)
                        notifyChangeObservers(RelationChange(added: added, removed: removed), kind: .directChange)
                    }
                    return .Ok(true)
                } catch {
                    return .Err(error)
                }
            })
        } else {
            return .Ok(false)
        }
    }
    
    public func deleteLocalFile(url: URL) -> Result<Bool, Swift.Error> {
        if urlMatches(url) {
            return readRow(url: url).then({ row in
                do {
                    try FileManager.default.removeItem(at: url)
                    
                    readCache.clear(url: url)
                    writeCache.clear(url: url)
                    
                    let removed = ConcreteRelation(row)
                    notifyChangeObservers(RelationChange(added: nil, removed: removed), kind: .directChange)
                    
                    return .Ok(true)
                } catch {
                    return .Err(error)
                }
            })
        } else {
            return .Ok(false)
        }
    }
    
    func urlMatches(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        
        guard let myComponents = self.url?.standardizedFileURL.pathComponents else { return false }
        let otherComponents = url.standardizedFileURL.pathComponents
        
        guard otherComponents.count >= myComponents.count else { return false }
        
        return zip(myComponents, otherComponents).all(==)
    }
}
