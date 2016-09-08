//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

open class ModelDatabase {
    open let sqliteDatabase: SQLiteDatabase
    
    /// A collection of all live model objects that came from this database. This lets multiple fetches
    /// for the same value return the same actual object instead of having to manage different objects
    /// representing the same value. I'm not sure yet if this is a good idea or not.
    ///
    /// The dictionary keys here are the Model types themselves. The values in the WeakValueDictionary
    /// are Model instances, but Swift generics don't let us use Model as the generic type here, so
    /// the type is just AnyObject instead.
    fileprivate var liveModelObjects: [ObjectIdentifier: WeakValueDictionary<ModelObjectID, AnyObject>] = [:]
    
    public init(_ sqliteDatabase: SQLiteDatabase) {
        self.sqliteDatabase = sqliteDatabase
    }
    
    open func contains<T: Model>(_ obj: T) -> Bool {
        if sqliteDatabase[type(of: obj).name] == nil {
            return false
        }
        
        let search = fetchAll(type(of: obj)).select(Attribute("objectID") *== RelationValue(obj.objectID.value))
        return search.makeIterator().next() != nil
    }
    
    open func add<T: Model>(_ obj: T) -> Result<Void, RelationError> {
        let relation = relationForModel(type(of: obj))
        return relation.then({
            $0.add(obj.toRow()).map({ _ in
                self.addLiveModelObject(obj)
            })
        })
    }
    
    open func fetchAll<T: Model>(_ type: T.Type) -> ModelRelation<T> {
        let relation = sqliteDatabase[type.name]!
        return ModelRelation(owningDatabase: self, underlyingRelation: relation)
    }
    
    open func fetch<T: Model, Parent: Model>(_ type: T.Type, ownedBy: Parent) -> Result<ModelToManyRelation<T>, RelationError> {
        let targetRelation = self.relationForModel(type)
        let joinRelation = self.joinRelation(from: Parent.self, to: type)
        
        return targetRelation.combine(joinRelation).map({// (targetRelation: Relation, joinRelation: Relation) -> ModelToManyRelation<T> in
            let joinRelationFiltered = $1.select(Attribute("from ID") *== RelationValue(ownedBy.objectID.value))
            
            let joined = joinRelationFiltered.equijoin($0, matching: ["to ID": "objectID"])
            return ModelToManyRelation(owningDatabase: self, underlyingRelation: joined, fromType: Parent.self, fromID: ownedBy.objectID)
        })
    }
    
    open func fetch<T: Model, Child: Model>(_ type: T.Type, owning child: Child) -> Result<ModelRelation<T>, RelationError> {
        let targetRelation = self.relationForModel(type)
        let joinRelation = self.joinRelation(from: type, to: Child.self)
        
        return targetRelation.combine(joinRelation).map({
            let joinRelationFiltered = $1.select(Attribute("to ID") *== RelationValue(child.objectID.value))
            
            let joined = joinRelationFiltered.equijoin($0, matching: ["from ID": "objectID"])
            return ModelRelation(owningDatabase: self, underlyingRelation: joined)
        })
    }
}

extension ModelDatabase {
    func relationForModel<T: Model>(_ type: T.Type) -> Result<SQLiteTableRelation, RelationError> {
        return sqliteDatabase.getOrCreateRelation(type.name, scheme: schemeForModel(type))
    }
    
    func joinRelation(from: Model.Type, to: Model.Type) -> Result<SQLiteTableRelation, RelationError> {
        let name = "\(from.name) to-many to \(to.name)"
        let scheme = Scheme(attributes: ["from ID", "to ID"])
        return sqliteDatabase.getOrCreateRelation(name, scheme: scheme)
    }
}

extension ModelDatabase {
    fileprivate func schemeForModel<T: Model>(_ type: T.Type) -> Scheme {
        return Scheme(attributes: Set(type.attributes))
    }
}

extension ModelDatabase {
    func getLiveModelObject<T: Model>(_ type: T.Type, _ objectID: ModelObjectID) -> T? {
        let obj = liveModelObjects[ObjectIdentifier(type)]?[objectID]
        return obj as! T?
    }
    
    func addLiveModelObject<T: Model>(_ obj: T) {
        let key = ObjectIdentifier(type(of: obj))
        if liveModelObjects[key] == nil {
            liveModelObjects[key] = WeakValueDictionary()
        }
        liveModelObjects[key]![obj.objectID] = obj
        
        obj.changeObservers.add({ self.modelChanged($0 as! T) })
    }
    
    func getOrMakeModelObject<T: Model>(_ type: T.Type, _ objectID: ModelObjectID, _ creatorFunction: (Void) -> Result<T, RelationError>) -> Result<T, RelationError> {
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

extension ModelDatabase {
    fileprivate func modelChanged<T: Model>(_ obj: T) {
        relationForModel(type(of: obj)).map({ $0.update(Attribute("objectID") *== RelationValue(obj.objectID.value), newValues: obj.toRow()) })
    }
}
