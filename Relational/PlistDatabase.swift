//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

protocol PlistRelation: StoredRelation {
    func save() -> Result<(), RelationError>
}

public class PlistDatabase: StoredDatabase {

    public enum RelationSpec { case
        file(name: String, path: String, scheme: Scheme),
        directory(name: String, path: String, scheme: Scheme, primaryKey: Attribute)
    }
    
    fileprivate var relations: Mutexed<[String: PlistRelation]>

    private init(relations: [String: PlistRelation]) {
        self.relations = Mutexed(relations)
    }

    private static func prepare(root: URL, specs: [RelationSpec], createIfDoesntExist: Bool) -> Result<PlistDatabase, RelationError> {

        func prepareRelation(_ spec: RelationSpec) -> Result<(String, PlistRelation), RelationError> {
            switch spec {
            case let .file(name, path, scheme):
                let url = root.appendingPathComponent(path, isDirectory: false)
                let result = PlistFileRelation.withFile(url, scheme: scheme, createIfDoesntExist: createIfDoesntExist)
                return result.map{ (name, $0) }
            case let .directory(name, path, scheme, primaryKey):
                let url = root.appendingPathComponent(path, isDirectory: true)
                let result = PlistDirectoryRelation.withDirectory(url, scheme: scheme, primaryKey: primaryKey, createIfDoesntExist: createIfDoesntExist)
                return result.map{ (name, $0) }
            }
        }
        
        return traverse(specs, prepareRelation).map{ PlistDatabase(relations: Dictionary($0)) }
    }
    
    public static func create(_ root: URL, _ specs: [RelationSpec]) -> Result<PlistDatabase, RelationError> {
        return prepare(root: root, specs: specs, createIfDoesntExist: true)
    }

    public static func open(_ root: URL, _ specs: [RelationSpec]) -> Result<PlistDatabase, RelationError> {
        return prepare(root: root, specs: specs, createIfDoesntExist: false)
    }
    
    public subscript(name: String) -> StoredRelation? {
        return storedRelation(forName: name)
    }

    public func storedRelation(forName name: String) -> StoredRelation? {
        return relations.withValue({ $0[name] })
    }
    
    public func transaction<Return>(_ transactionFunction: (Void) -> (Return, TransactionResult)) -> Result<Return, RelationError> {
        // TODO: Coordinate things so that we only save relations that have been dirtied
        let transactionResult = transactionFunction()
        var result: Result<Return, RelationError> = .Ok(transactionResult.0)
        relations.withValue{
            for relation in $0.values {
                if let saveError = relation.save().err {
                    result = .Err(saveError)
                    break
                }
            }
        }
        return result
    }
    
    public func resultNeedsRetry<T>(_ result: Result<T, RelationError>) -> Bool {
        return false
    }
}
