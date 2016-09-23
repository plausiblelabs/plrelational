//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

protocol PlistRelation: StoredRelation {
    var url: URL? { get set }
    func save() -> Result<(), RelationError>
}

public class PlistDatabase: StoredDatabase {

    public enum RelationSpec { case
        file(name: String, path: String, scheme: Scheme),
        directory(name: String, path: String, scheme: Scheme, primaryKey: Attribute)
        
        public var path: String {
            switch self {
            case let .file(_, path, _):
                return path
            case let .directory(_, path, _, _):
                return path
            }
        }
        
        public func url(withRoot root: URL?) -> URL? {
            switch self {
            case .file:
                return root?.appendingPathComponent(path, isDirectory: false)
            case .directory:
                return root?.appendingPathComponent(path, isDirectory: true)
            }
        }
    }
    
    private typealias ManagedRelation = (spec: RelationSpec, relation: PlistRelation)
    
    public var root: URL?
    private var relations: Mutexed<[String: ManagedRelation]>

    private init(root: URL?, relations: [String: ManagedRelation]) {
        self.root = root
        self.relations = Mutexed(relations)
    }

    private static func prepare(root: URL?, specs: [RelationSpec], createIfDoesntExist: Bool) -> Result<PlistDatabase, RelationError> {

        func prepareRelation(_ spec: RelationSpec) -> Result<(String, ManagedRelation), RelationError> {
            let url = spec.url(withRoot: root)
            switch spec {
            case let .file(name, _, scheme):
                let result = PlistFileRelation.withFile(url, scheme: scheme, createIfDoesntExist: createIfDoesntExist)
                return result.map{ (name, (spec: spec, relation: $0)) }
            case let .directory(name, _, scheme, primaryKey):
                let result = PlistDirectoryRelation.withDirectory(url, scheme: scheme, primaryKey: primaryKey, createIfDoesntExist: createIfDoesntExist)
                return result.map{ (name, (spec: spec, relation: $0)) }
            }
        }
        
        return traverse(specs, prepareRelation).map{ PlistDatabase(root: root, relations: Dictionary($0)) }
    }
    
    public static func create(_ root: URL?, _ specs: [RelationSpec]) -> Result<PlistDatabase, RelationError> {
        return prepare(root: root, specs: specs, createIfDoesntExist: true)
    }

    public static func open(_ root: URL, _ specs: [RelationSpec]) -> Result<PlistDatabase, RelationError> {
        return prepare(root: root, specs: specs, createIfDoesntExist: false)
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
}
