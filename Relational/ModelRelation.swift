
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
    let joinRelation: SQLiteTableRelation
    let fromID: Int64
    
    init(owningDatabase: ModelDatabase, underlyingRelation: Relation, joinRelation: SQLiteTableRelation, fromID: Int64) {
        self.joinRelation = joinRelation
        self.fromID = fromID
        super.init(owningDatabase: owningDatabase, underlyingRelation: underlyingRelation)
    }
    
    func add(obj: T) throws {
        if obj.objectID == nil {
            try owningDatabase.add(obj)
        }
        try joinRelation.add(["from ID": RelationValue(fromID), "to ID": RelationValue(obj.objectID!)])
    }
}