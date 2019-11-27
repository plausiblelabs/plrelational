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
    
    public var debugName: String?
    
    public let saveObservers = RemovableSet<(URL) -> Void>()
    
    fileprivate init(scheme: Scheme, primaryKeys: [Attribute], url: URL?, codec: DataCodec?, isTransient: Bool) {
        self.scheme = scheme
        self.values = IndexedSet(primaryKeys: primaryKeys)
        self.url = url
        self.isTransient = isTransient
        self.codec = codec
    }
    
    public var contentProvider: RelationContentProvider {
        return values.contentProvider
    }
    
    public func contains(_ row: Row) -> Result<Bool, RelationError> {
        return .Ok(values.contains(row))
    }
    
    public func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let toUpdate = values.valuesMatching(expression: query)
        values.subtractInPlace(toUpdate)
        
        let updated = Set(toUpdate.map({ $0.rowWithUpdate(newValues) }))
        values.unionInPlace(updated)
        
        let added = ConcreteRelation(scheme: self.scheme, values: updated - toUpdate)
        let removed = ConcreteRelation(scheme: self.scheme, values: toUpdate - updated)
        
        notifyChangeObservers(RelationChange(added: added, removed: removed), kind: .directChange)
        
        return .Ok(())
    }
    
    public func add(_ row: Row) -> Result<Int64, RelationError> {
        if !values.contains(row) {
            values.add(element: row)
            notifyChangeObservers(RelationChange(added: ConcreteRelation(row), removed: nil), kind: .directChange)
        }
        return .Ok(0)
    }
    
    public func delete(_ query: SelectExpression) -> Result<Void, RelationError> {
        let toDelete = values.valuesMatching(expression: query)
        values.subtractInPlace(toDelete)
        notifyChangeObservers(RelationChange(added: nil, removed: ConcreteRelation(scheme: scheme, values: toDelete)), kind: .directChange)
        return .Ok(())
    }
}

extension PlistFileRelation {
    public enum Error: Swift.Error {
        case unknownTopLevelObject(unknownObject: Any)
        case missingValues
        case unknownValuesObject(unknownObject: Any)
        case schemeMismatch(foundScheme: Scheme)
    }
    
    /// Create a new relation with the given file.
    ///
    /// - Parameters:
    ///   - url: The URL to the file to use. If nil, the relation starts out empty, and
    ///          the `url` property must be set before calling `save()`.
    ///   - scheme: The relation scheme.
    ///   - primaryKeys: The primary keys to use for the relation. Queries involving these
    ///                  keys can be resolved without scanning every row in the relation.
    ///                  Each primary key involves extra bookkeeping time and space, so
    ///                  it is not always desirable to put every key in the scheme in.
    ///   - create: If false, then a URL must be provided and it must point to an existing
    ///             file. If no URL is provided, this is a precondition failure. If an URL
    ///             is provided but the file doesn't exist or isn't readable, this is an error.
    ///             If true, then the file doesn't have to exist. If it does exist, its contents
    ///             are loaded into the relation.
    ///   - codec: A DataCodec used to encode and decode the plist on disk.
    /// - Returns: The newly created file relation, or an error if creation failed.
    public static func withFile(_ url: URL?, scheme: Scheme, primaryKeys: [Attribute], create: Bool, codec: DataCodec? = nil) -> Result<PlistFileRelation, RelationError> {
        if let url = url {
            // We have a URL, so we are either opening an existing relation or creating a new one at a specific location;
            do {
                let data = try Data(contentsOf: url, options: [])
                let decodedDataResult = codec?.decode(data) ?? .Ok(data)
                return try decodedDataResult.then({
                    let plist = try PropertyListSerialization.propertyList(from: $0, options: [], format: nil)
                    guard let dict = plist as? NSDictionary else { return .Err(Error.unknownTopLevelObject(unknownObject: plist)) }
                    
                    guard let values = dict["values"] else { return .Err(Error.missingValues) }
                    guard let array = values as? NSArray else { return .Err(Error.unknownValuesObject(unknownObject: values)) }
                    
                    let relationValueResults = array.map({
                        Row.fromPlist($0).then({
                            return $0.scheme == scheme
                                ? .Ok($0)
                                : .Err(Error.schemeMismatch(foundScheme: $0.scheme))
                        })
                    })
                    let relationValuesResult = mapOk(relationValueResults, { $0 })
                    return relationValuesResult.map({
                        let r = PlistFileRelation(scheme: scheme, primaryKeys: primaryKeys, url: url, codec: codec, isTransient: false)
                        r.values.unionInPlace($0)
                        return r
                    })
                })
            } catch {
                // If create is true and the error is file not found, then the error is not fatal.
                // Let execution proceed. Otherwise, return the error.
                if !(create && error.isFileNotFound) {
                    return .Err(error)
                }
            }
        } else {
            // We have no URL, so we are creating a new relation; we will defer file creation until the first save
            precondition(create)
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
}

extension PlistFileRelation {
    public func replaceLocalFile(url: URL, movingURL: URL) -> Result<Bool, Swift.Error> {
        if urlMatches(url) {
            let replacementRelation = PlistFileRelation.withFile(movingURL, scheme: scheme, primaryKeys: Array(values.primaryKeys), create: false, codec: codec)
            return replacementRelation.then({ replacementRelation in
                do {
                    _ = try FileManager.default.replaceItemAt(url, withItemAt: movingURL)
                    
                    let existingRows = self.values.values
                    let replacementRows = replacementRelation.values.values
                    
                    let added = ConcreteRelation(scheme: self.scheme, values: replacementRows - existingRows)
                    let removed = ConcreteRelation(scheme: self.scheme, values: existingRows - replacementRows)
                    
                    self.values = replacementRelation.values
                    
                    self.notifyChangeObservers(RelationChange(added: added, removed: removed), kind: .directChange)
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
            do {
                try FileManager.default.removeItem(at: url)
                return delete(true).map({ true })
            } catch {
                return .Err(error)
            }
        } else {
            return .Ok(false)
        }
    }
    
    private func urlMatches(_ url: URL) -> Bool {
        return url.standardizedFileURL == self.url?.standardizedFileURL
    }
}
