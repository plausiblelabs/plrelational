
protocol Model: class {
    static var name: String { get }
    static var attributes: [Attribute] { get }
    
    var owningDatabase: ModelDatabase { get }
    
    func toRow() -> Row
    static func fromRow(owningDatabase: ModelDatabase, _ row: Row) throws -> Self
    
    var objectID: Int64? { get set }
}

extension Model {
    func parentsOfType<T: Model>(type: T.Type) throws -> ModelRelation<T> {
        return try owningDatabase.fetch(type, owning: self)
    }
    
    func parentOfType<T: Model>(type: T.Type) throws -> T? {
        let parents = try parentsOfType(type)
        let gen = parents.generate()
        
        // Get one parent.
        guard let result = gen.next() else { return nil }
        
        // Ensure there's only one. If there's two, bail.
        guard gen.next() == nil else { return nil }
        
        return result
    }
}
