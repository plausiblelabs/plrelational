//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public protocol Model: class {
    static var name: String { get }
    static var attributes: [Attribute] { get }
    
    var owningDatabase: ModelDatabase { get }
    
    var changeObservers: ObserverSet<Model> { get }
    
    var objectID: ModelObjectID { get set }
    
    func toRow() -> Row
    static func fromRow(_ owningDatabase: ModelDatabase, _ row: Row) -> Result<Self, RelationError>
}

extension Model {
    public func parentsOfType<T: Model>(_ type: T.Type) -> Result<ModelRelation<T>, RelationError> {
        return owningDatabase.fetch(type, owning: self)
    }
    
    public func parentOfType<T: Model>(_ type: T.Type) -> Result<T?, RelationError> {
        return parentsOfType(type).then({ parents in
            let gen = parents.makeIterator()
            
            // Get one parent.
            guard let result = gen.next() else { return .Ok(nil) }
            
            // Ensure there's only one. If there's two, bail.
            guard gen.next() == nil else { return .Ok(nil) }
            
            // The map call makes the type optional, otherwise Result<T> isn't compatible with Result<T?>
            return result.map({ $0 })
        })
    }
}

public struct ModelObjectID {
    public var value: [UInt8]
    
    public init(value: [UInt8]) {
        self.value = value
    }
    
    public static func new() -> ModelObjectID {
        let uuidLength = 16
        var result = ModelObjectID(value: Array(repeating: 0, count: uuidLength))
        (UUID() as NSUUID).getBytes(&result.value)
        return result
    }
}

extension ModelObjectID: CustomStringConvertible {
    public var description: String {
        let result = NSMutableString()
        for byte in value {
            result.appendFormat("%02x", byte)
        }
        return result as String
    }
}

extension ModelObjectID: Equatable {}
public func ==(a: ModelObjectID, b: ModelObjectID) -> Bool {
    return a.value == b.value
}

extension ModelObjectID: Hashable {
    public var hashValue: Int {
        return value.hashValueFromElements
    }
}
