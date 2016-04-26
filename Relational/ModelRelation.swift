
class ModelRelation<T: Model>: SequenceType {
    let owningDatabase: ModelDatabase
    
    let underlyingRelation: Relation
    
    init(owningDatabase: ModelDatabase, underlyingRelation: Relation) {
        self.owningDatabase = owningDatabase
        self.underlyingRelation = underlyingRelation
    }
    
    func generate() -> AnyGenerator<Result<T, RelationError>> {
        let rows = underlyingRelation.rows()
        return AnyGenerator(body: {
            if let row = rows.next() {
                return row.then({ T.fromRow(self.owningDatabase, $0) })
            } else {
                return nil
            }
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
    
    func add(obj: T) -> Result<Void, RelationError> {
        if !owningDatabase.contains(obj) {
            if let error = owningDatabase.add(obj).err {
                return .Err(error)
            }
        }
        
        let joinRelation = owningDatabase.joinRelation(from: fromType, to: T.self)
        let result = joinRelation.add(["from ID": RelationValue(fromID.value), "to ID": RelationValue(obj.objectID.value)])
        return result.map({ _ in })
    }
}