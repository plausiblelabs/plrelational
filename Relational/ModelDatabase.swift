
class ModelDatabase {
    let sqliteDatabase: SQLiteDatabase
    
    /// A collection of all live model objects that came from this database. This lets multiple fetches
    /// for the same value return the same actual object instead of having to manage different objects
    /// representing the same value. I'm not sure yet if this is a good idea or not.
    ///
    /// The dictionary keys here are the Model types themselves. The values in the WeakValueDictionary
    /// are Model instances, but Swift generics don't let us use Model as the generic type here, so
    /// the type is just AnyObject instead.
    private var liveModelObjects: [ObjectIdentifier: WeakValueDictionary<ModelObjectID, AnyObject>] = [:]
    
    init(_ sqliteDatabase: SQLiteDatabase) {
        self.sqliteDatabase = sqliteDatabase
    }
    
    func contains<T: Model>(obj: T) -> Bool {
        if !sqliteDatabase.tables.contains(obj.dynamicType.name) {
            return false
        }
        
        let search = fetchAll(obj.dynamicType).select([.EQ(Attribute("objectID"), RelationValue(obj.objectID.value))])
        return search.generate().next() != nil
    }
    
    func add(obj: Model) -> Result<Void, RelationError> {
        let relation = relationForModel(obj.dynamicType)
        return relation.add(obj.toRow()).map({ _ in
            self.addLiveModelObject(obj)
        })
    }
    
    func fetchAll<T: Model>(type: T.Type) -> ModelRelation<T> {
        let relation = sqliteDatabase[type.name, schemeForModel(type)]
        return ModelRelation(owningDatabase: self, underlyingRelation: relation)
    }
    
    func fetch<T: Model, Parent: Model>(type: T.Type, ownedBy: Parent) -> ModelToManyRelation<T> {
        let targetRelation = self.relationForModel(type)
        let joinRelation = self.joinRelation(from: Parent.self, to: type)
        
        let joinRelationFiltered = joinRelation.select([.EQ(Attribute("from ID"), RelationValue(ownedBy.objectID.value))])
        
        let joined = joinRelationFiltered.equijoin(targetRelation, matching: ["to ID": "objectID"])
        return ModelToManyRelation(owningDatabase: self, underlyingRelation: joined, fromType: Parent.self, fromID: ownedBy.objectID)
    }
    
    func fetch<T: Model, Child: Model>(type: T.Type, owning child: Child) -> ModelRelation<T> {
        let targetRelation = self.relationForModel(type)
        let joinRelation = self.joinRelation(from: type, to: Child.self)
        
        let joinRelationFiltered = joinRelation.select([.EQ(Attribute("to ID"), RelationValue(child.objectID.value))])
        
        let joined = joinRelationFiltered.equijoin(targetRelation, matching: ["from ID": "objectID"])
        return ModelRelation(owningDatabase: self, underlyingRelation: joined)
    }
}

extension ModelDatabase {
    func relationForModel(type: Model.Type) -> SQLiteTableRelation {
        return sqliteDatabase[type.name, schemeForModel(type)]
    }
    
    func joinRelation(from from: Model.Type, to: Model.Type) -> SQLiteTableRelation {
        let name = "\(from.name) to-many to \(to.name)"
        let scheme = Scheme(attributes: ["from ID", "to ID"])
        return sqliteDatabase[name, scheme]
    }
}

extension ModelDatabase {
    private func schemeForModel(type: Model.Type) -> Scheme {
        return Scheme(attributes: Set(type.attributes))
    }
}

extension ModelDatabase {
    func getLiveModelObject<T: Model>(type: T.Type, _ objectID: ModelObjectID) -> T? {
        let obj = liveModelObjects[ObjectIdentifier(type)]?[objectID]
        return obj as! T?
    }
    
    func addLiveModelObject(obj: Model) {
        let key = ObjectIdentifier(obj.dynamicType)
        if liveModelObjects[key] == nil {
            liveModelObjects[key] = WeakValueDictionary()
        }
        liveModelObjects[key]![obj.objectID] = obj
    }
    
    func getOrMakeModelObject<T: Model>(type: T.Type, _ objectID: ModelObjectID, _ creatorFunction: Void -> Result<T, RelationError>) -> Result<T, RelationError> {
        if let obj = getLiveModelObject(type, objectID) {
            return .Ok(obj)
        }
        
        let result = creatorFunction()
        if let obj = result.ok {
            addLiveModelObject(obj)
        }
        return result
    }
}
