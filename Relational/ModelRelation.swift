
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
            return rows.next().map({ T.fromRow(self.owningDatabase, $0) })
        })
    }
}

extension ModelRelation {
    func select(terms: [ComparisonTerm]) -> ModelRelation {
        return ModelRelation(owningDatabase: owningDatabase, underlyingRelation: underlyingRelation.select(terms))
    }
}
