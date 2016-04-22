
class ModelDatabase {
    let sqliteDatabase: SQLiteDatabase
    
    init(_ sqliteDatabase: SQLiteDatabase) {
        self.sqliteDatabase = sqliteDatabase
    }
    
    func add(obj: Model) throws {
        precondition(obj.objectID == nil, "Can't insert an object that already has an ID")
        
        let relation = try getOrCreateRelation(obj.dynamicType)
        let objectID = try relation.add(obj.toRow())
        
        obj.objectID = objectID
    }
    
    func fetchAll<T: Model>(type: T.Type) throws -> ModelRelation<T> {
        let relation = try getOrCreateRelation(type)
        return ModelRelation(underlyingRelation: relation)
    }
}

extension ModelDatabase {
    private func getOrCreateRelation(type: Model.Type) throws -> SQLiteTableRelation {
        let allAttributes = type.attributes + [Attribute("objectID")]
        let scheme = Scheme(attributes: Set(allAttributes))
        try sqliteDatabase.createRelation(type.name, scheme: scheme, rowidAttribute: Attribute("objectID"))
        return sqliteDatabase[type.name]
    }
}
