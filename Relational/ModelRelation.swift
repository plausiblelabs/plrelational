
class ModelRelation<T: Model>: SequenceType {
    let underlyingRelation: Relation
    
    init(underlyingRelation: Relation) {
        self.underlyingRelation = underlyingRelation
    }
    
    func generate() -> AnyGenerator<T> {
        let rows = underlyingRelation.rows()
        return AnyGenerator(body: {
            return rows.next().map(T.fromRow)
        })
    }
}
