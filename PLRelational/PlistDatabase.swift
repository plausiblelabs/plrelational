//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

protocol PlistRelation: StoredRelation {
    var url: URL? { get set }
    var saveObservers: RemovableSet<(URL) -> Void> { get }
    func save() -> Result<(), RelationError>
    
    func replaceLocalFile(url: URL, movingURL: URL) -> Result<Bool, Error>
    func deleteLocalFile(url: URL) -> Result<Bool, Error>
}

public class PlistDatabase: StoredDatabase {

    public enum RelationSpec {
        case transient(name: String, scheme: Scheme, primaryKeys: [Attribute])
        case file(name: String, path: String, scheme: Scheme, primaryKeys: [Attribute])
        case directory(name: String, path: String, scheme: Scheme, primaryKey: Attribute)

        public var name: String {
            switch self {
            case let .transient(name, _, _): return name
            case let .file(name, _, _, _): return name
            case let .directory(name, _, _, _): return name
            }
        }

        public func url(withRoot root: URL?) -> URL? {
            switch self {
            case .transient:
                return nil
            case let .file(_, path, _, _):
                return root?.appendingPathComponent(path, isDirectory: false)
            case let .directory(_, path, _, _):
                return root?.appendingPathComponent(path, isDirectory: true)
            }
        }
    }
    
    private typealias ManagedRelation = (spec: RelationSpec, relation: PlistRelation)
    
    public var root: URL?
    private var relations: Mutexed<[String: ManagedRelation]>

    private init(root: URL?, relations: [String: ManagedRelation]) {
        self.root = root
        relations.forEach({ _ = $1.1.setDebugName($0) })
        self.relations = Mutexed(relations)
    }

    private static func prepare(root: URL?, specs: [RelationSpec], codec: DataCodec?, create: Bool) -> Result<PlistDatabase, RelationError> {

        func prepareRelation(_ spec: RelationSpec) -> Result<(String, ManagedRelation), RelationError> {
            let url = spec.url(withRoot: root)
            switch spec {
            case let .transient(name, scheme, primaryKeys):
                let relation = PlistFileRelation.transient(scheme: scheme, primaryKeys: primaryKeys, codec: codec) as PlistRelation
                return .Ok((name, (spec: spec, relation: relation)))
            case let .file(name, _, scheme, primaryKeys):
                let result = PlistFileRelation.withFile(url, scheme: scheme, primaryKeys: primaryKeys, create: create, codec: codec)
                return result.map{ (name, (spec: spec, relation: $0)) }
            case let .directory(name, _, scheme, primaryKey):
                let result = PlistDirectoryRelation.withDirectory(url, scheme: scheme, primaryKey: primaryKey, create: create, codec: codec)
                return result.map{ (name, (spec: spec, relation: $0)) }
            }
        }
        
        return traverse(specs, prepareRelation).map{ PlistDatabase(root: root, relations: Dictionary($0)) }
    }
    
    public static func create(_ root: URL?, _ specs: [RelationSpec], codec: DataCodec? = nil) -> Result<PlistDatabase, RelationError> {
        return prepare(root: root, specs: specs, codec: codec, create: true)
    }

    public static func open(_ root: URL, _ specs: [RelationSpec], codec: DataCodec? = nil) -> Result<PlistDatabase, RelationError> {
        return prepare(root: root, specs: specs, codec: codec, create: false)
    }
    
    public subscript(name: String) -> StoredRelation? {
        return storedRelation(forName: name)
    }

    public func storedRelation(forName name: String) -> StoredRelation? {
        return relations.withValue({ $0[name]?.relation })
    }
    
    public func transaction<Return>(_ transactionFunction: (Void) -> (Return, TransactionResult)) -> Result<Return, RelationError> {
        // Ensure that all relations have a valid URL before we continue
        switch validateRelations() {
        case .Ok:
            // TODO: Coordinate things so that we only save relations that have been dirtied
            let transactionResult = transactionFunction()
            return saveRelations().map{ transactionResult.0 }
        case let .Err(error):
            return .Err(error)
        }
    }
    
    public func resultNeedsRetry<T>(_ result: Result<T, RelationError>) -> Bool {
        return false
    }
    
    /// Iterates over all managed relations and ensures that each relation's URL is set relative to the current
    /// root URL.
    public func validateRelations() -> Result<(), RelationError> {
        guard let root = root else { fatalError("Root URL must be set prior to performing transaction") }

        // Make sure the root directory exists before we continue
        if !(root as NSURL).checkResourceIsReachableAndReturnError(nil) {
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return .Err(error)
            }
        }

        // Check each relation's URL
        relations.withMutableValue{
            for managed in $0.values {
                let relation = managed.relation
                if relation.url == nil {
                    relation.url = managed.spec.url(withRoot: root)
                }
            }
        }
        
        return .Ok(())
    }
    
    /// Iterates over all managed relations and saves each one to disk, if needed.
    public func saveRelations() -> Result<(), RelationError> {
        var result: Result<(), RelationError> = .Ok(())
        relations.withValue{
            for managed in $0.values {
                if let saveError = managed.relation.save().err {
                    result = .Err(saveError)
                    break
                }
            }
        }
        return result
    }
    
    public func addSaveObserver(_ observer: @escaping (URL) -> Void) {
        relations.withValue({
            for managed in $0.values {
                _ = managed.relation.saveObservers.add(observer)
            }
        })
    }
    
    /// Replace a local file within the doc database with a new file.
    /// Returns `true` if the replacement was done, and `false` if
    /// the local file isn't part of the doc database.
    public func replaceLocalFile(url: URL, movingURL: URL) -> Result<Bool, Error> {
        return relations.withValue({
            for (key: _, value: (spec: _, relation: r)) in $0 {
                let result = r.replaceLocalFile(url: url, movingURL: movingURL)
                if result.ok == true || result.err != nil {
                    return result
                }
            }
            return .Ok(false)
        })
    }
    
    /// Delete a local file within the doc database.
    /// Returns `true` if the deletion was done, and `false` if
    /// the local file isn't part of the doc database.
    public func deleteLocalFile(url: URL) -> Result<Bool, Error> {
        return relations.withValue({
            for (key: _, value: (spec: _, relation: r)) in $0 {
                let result = r.deleteLocalFile(url: url)
                if result.ok == true || result.err != nil {
                    return result
                }
            }
            return .Ok(false)
        })
    }
}
