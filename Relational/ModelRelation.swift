
class ModelRelation<T: Model>: SequenceType {
    let owningDatabase: ModelDatabase
    
    let underlyingRelation: Relation
    
    init(owningDatabase: ModelDatabase, underlyingRelation: Relation) {
        self.owningDatabase = owningDatabase
        self.underlyingRelation = underlyingRelation
    }
    
    func generate() -> AnyGenerator<T> {
        let rows = underlyingRelation.rows()
        return AnyGenerator(body: {
            return rows.next().map({ try! T.fromRow(self.owningDatabase, $0) })
        })
    }
}

extension ModelRelation {
    func select(terms: [ComparisonTerm]) -> ModelRelation {
        return ModelRelation(owningDatabase: owningDatabase, underlyingRelation: underlyingRelation.select(terms))
    }
}

class ModelToManyRelation<T: Model>: ModelRelation<T> {
    let fromType: Model.Type
    let fromID: ModelObjectID
    
    init(owningDatabase: ModelDatabase, underlyingRelation: Relation, fromType: Model.Type, fromID: ModelObjectID) {
        self.fromType = fromType
        self.fromID = fromID
        super.init(owningDatabase: owningDatabase, underlyingRelation: underlyingRelation)
    }
    
    func add(obj: T) throws {
        if !owningDatabase.contains(obj) {
            try owningDatabase.add(obj)
        }
        
        let joinRelation = owningDatabase.joinRelation(from: fromType, to: T.self)
        try joinRelation.add(["from ID": RelationValue(fromID.value), "to ID": RelationValue(obj.objectID.value)])
    }
}