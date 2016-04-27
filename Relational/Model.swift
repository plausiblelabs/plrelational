
import Foundation

protocol Model: class {
    static var name: String { get }
    static var attributes: [Attribute] { get }
    
    var owningDatabase: ModelDatabase { get }
    
    func toRow() -> Row
    static func fromRow(owningDatabase: ModelDatabase, _ row: Row) -> Result<Self, RelationError>
    
    var objectID: ModelObjectID { get set }
}

extension Model {
    func parentsOfType<T: Model>(type: T.Type) -> ModelRelation<T> {
        return owningDatabase.fetch(type, owning: self)
    }
    
    func parentOfType<T: Model>(type: T.Type) -> Result<T?, RelationError> {
        let parents = parentsOfType(type)
        let gen = parents.generate()
        
        // Get one parent.
        guard let result = gen.next() else { return .Ok(nil) }
        
        // Ensure there's only one. If there's two, bail.
        guard gen.next() == nil else { return .Ok(nil) }
        
        // The map call makes the type optional, otherwise Result<T> isn't compatible with Result<T?>
        return result.map({ $0 })
    }
}

struct ModelObjectID {
    var value: [UInt8]
    
    static func new() -> ModelObjectID {
        let uuidLength = 16
        var result = ModelObjectID(value: Array(count: uuidLength, repeatedValue: 0))
        NSUUID().getUUIDBytes(&result.value)
        return result
    }
}

extension ModelObjectID: CustomStringConvertible {
    var description: String {
        let result = NSMutableString()
        for byte in value {
            result.appendFormat("%02x", byte)
        }
        return result as String
    }
}

extension ModelObjectID: Equatable {}
func ==(a: ModelObjectID, b: ModelObjectID) -> Bool {
    return a.value == b.value
}

extension ModelObjectID: Hashable {
    var hashValue: Int {
        return value.hashValueFromElements
    }
}
