
class ModelDatabase {
    let sqliteDatabase: SQLiteDatabase
    
    init(_ sqliteDatabase: SQLiteDatabase) {
        self.sqliteDatabase = sqliteDatabase
    }
    
    func contains<T: Model>(obj: T) throws -> Bool {
        let search = try fetchAll(obj.dynamicType).select([.EQ(Attribute("objectID"), RelationValue(obj.objectID.value))])
        return search.generate().next() != nil
    }
    
    func add(obj: Model) throws {
        let relation = try getOrCreateRelation(obj.dynamicType)
        try relation.add(obj.toRow())
    }
    
    func fetchAll<T: Model>(type: T.Type) throws -> ModelRelation<T> {
        let relation = try getOrCreateRelation(type)
        return ModelRelation(owningDatabase: self, underlyingRelation: relation)
    }
    
    func fetch<T: Model, Parent: Model>(type: T.Type, ownedBy: Parent) throws -> ModelToManyRelation<T> {
        let targetRelation = try getOrCreateRelation(type)
        let joinRelation = try getOrCreateToManyJoinRelation(from: Parent.self, to: type)
        
        let joinRelationFiltered = joinRelation.select([.EQ(Attribute("from ID"), RelationValue(ownedBy.objectID.value))])
        
        let joined = joinRelationFiltered.equijoin(targetRelation, matching: ["to ID": "objectID"])
        return ModelToManyRelation(owningDatabase: self, underlyingRelation: joined, joinRelation: joinRelation, fromID: ownedBy.objectID)
    }
    
    func fetch<T: Model, Child: Model>(type: T.Type, owning child: Child) throws -> ModelRelation<T> {
        let targetRelation = try getOrCreateRelation(type)
        let joinRelation = try getOrCreateToManyJoinRelation(from: type, to: Child.self)
        
        let joinRelationFiltered = joinRelation.select([.EQ(Attribute("to ID"), RelationValue(child.objectID.value))])
        
        let joined = joinRelationFiltered.equijoin(targetRelation, matching: ["from ID": "objectID"])
        return ModelRelation(owningDatabase: self, underlyingRelation: joined)
    }
}

extension ModelDatabase {
    func getOrCreateRelation(type: Model.Type) throws -> SQLiteTableRelation {
        let allAttributes = type.attributes + [Attribute("objectID")]
        let scheme = Scheme(attributes: Set(allAttributes))
        try sqliteDatabase.createRelation(type.name, scheme: scheme)
        return sqliteDatabase[type.name]
    }
}

extension ModelDatabase {
    func getOrCreateToManyJoinRelation(from from: Model.Type, to: Model.Type) throws -> SQLiteTableRelation {
        let name = "\(from.name) to-many to \(to.name)"
        let scheme = Scheme(attributes: ["from ID", "to ID"])
        try sqliteDatabase.createRelation(name, scheme: scheme)
        return sqliteDatabase[name]
    }
}
