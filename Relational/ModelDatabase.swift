
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
        return ModelRelation(owningDatabase: self, underlyingRelation: relation)
    }
    
    func fetch<T: Model, Parent: Model>(type: T.Type, ownedBy: Parent) throws -> ModelToManyRelation<T> {
        guard let ownerID = ownedBy.objectID else { fatalError("Can't fetch to-many target for an object with no ID") }
        
        let targetRelation = try getOrCreateRelation(type)
        let joinRelation = try getOrCreateToManyJoinRelation(from: Parent.self, to: type)
        
        let joinRelationFiltered = joinRelation.select([.EQ(Attribute("from ID"), String(ownerID))])
        
        let joined = joinRelationFiltered.equijoin(targetRelation, matching: ["to ID": "objectID"])
        return ModelToManyRelation(owningDatabase: self, underlyingRelation: joined, joinRelation: joinRelation, fromID: ownerID)
    }
    
    func fetch<T: Model, Child: Model>(type: T.Type, owning child: Child) throws -> ModelRelation<T> {
        guard let childID = child.objectID else { fatalError("Can't fetch to-many target for an object with no ID") }
        
        let targetRelation = try getOrCreateRelation(type)
        let joinRelation = try getOrCreateToManyJoinRelation(from: type, to: Child.self)
        
        let joinRelationFiltered = joinRelation.select([.EQ(Attribute("to ID"), String(childID))])
        
        let joined = joinRelationFiltered.equijoin(targetRelation, matching: ["from ID": "objectID"])
        return ModelRelation(owningDatabase: self, underlyingRelation: joined)
    }
}

extension ModelDatabase {
    func getOrCreateRelation(type: Model.Type) throws -> SQLiteTableRelation {
        let allAttributes = type.attributes + [Attribute("objectID")]
        let scheme = Scheme(attributes: Set(allAttributes))
        try sqliteDatabase.createRelation(type.name, scheme: scheme, rowidAttribute: Attribute("objectID"))
        return sqliteDatabase[type.name]
    }
}

extension ModelDatabase {
    func getOrCreateToManyJoinRelation(from from: Model.Type, to: Model.Type) throws -> SQLiteTableRelation {
        let name = "\(from.name) to-many to \(to.name)"
        let scheme = Scheme(attributes: ["from ID", "to ID"])
        try sqliteDatabase.createRelation(name, scheme: scheme, rowidAttribute: nil)
        return sqliteDatabase[name]
    }
}
