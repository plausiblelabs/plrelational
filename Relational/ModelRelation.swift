//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public class ModelRelation<T: Model>: SequenceType {
    let owningDatabase: ModelDatabase
    
    let underlyingRelation: Relation
    
    init(owningDatabase: ModelDatabase, underlyingRelation: Relation) {
        self.owningDatabase = owningDatabase
        self.underlyingRelation = underlyingRelation
    }
    
    public func generate() -> AnyGenerator<Result<T, RelationError>> {
        let rows = underlyingRelation.rows()
        return AnyGenerator(body: {
            if let row = rows.next() {
                return row.then({ row in
                    guard let objectID: [UInt8] = row["objectID"].get() else {
                        return .Err(ModelError.BadDataType(attribute: "objectID"))
                    }
                    return self.owningDatabase.getOrMakeModelObject(T.self, ModelObjectID(value: objectID), {
                        T.fromRow(self.owningDatabase, row)
                    })
                })
            } else {
                return nil
            }
        })
    }
}

extension ModelRelation {
    public func select(query: SelectExpression) -> ModelRelation {
        return ModelRelation(owningDatabase: owningDatabase, underlyingRelation: underlyingRelation.select(query))
    }
}

public class ModelToManyRelation<T: Model>: ModelRelation<T> {
    let fromType: Model.Type
    let fromID: ModelObjectID
    
    init(owningDatabase: ModelDatabase, underlyingRelation: Relation, fromType: Model.Type, fromID: ModelObjectID) {
        self.fromType = fromType
        self.fromID = fromID
        super.init(owningDatabase: owningDatabase, underlyingRelation: underlyingRelation)
    }
    
    public func add(obj: T) -> Result<Void, RelationError> {
        if !owningDatabase.contains(obj) {
            if let error = owningDatabase.add(obj).err {
                return .Err(error)
            }
        }
        
        let joinRelation = owningDatabase.joinRelation(from: fromType, to: T.self)
        let result = joinRelation.then({ $0.add(["from ID": RelationValue(fromID.value), "to ID": RelationValue(obj.objectID.value)]) })
        return result.map({ _ in })
    }
}