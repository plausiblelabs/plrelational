
public class SQLiteBinding {
    public enum Error: ErrorType {
        case NoRows
    }
    
    let database: SQLiteDatabase
    let tableName: String
    let scheme: Scheme
    let key: Row
    let attribute: Attribute
    let changeObserver: RelationValue -> Void
    
    let relation: Relation
    
    var removal: (Void -> Void)?
    
    public init(database: SQLiteDatabase, tableName: String, scheme: Scheme, key: Row, attribute: Attribute, changeObserver: RelationValue -> Void) {
        self.database = database
        self.tableName = tableName
        self.scheme = scheme
        self.key = key
        self.attribute = attribute
        self.changeObserver = changeObserver
        
        self.relation = database[tableName, scheme].select(key)
        self.removal = self.relation.addChangeObserver({ [weak self] in self?.changed() })
        
        self.changed()
    }
    
    deinit {
        self.removal?()
    }
    
    public func get() -> Result<RelationValue, RelationError> {
        return self.relation.rows().generate().next()?.map({ $0[attribute] }) ?? .Err(Error.NoRows)
    }
    
    public func set(value: RelationValue) -> Result<Void, RelationError> {
        let searchTerms = key.values.map({ ComparisonTerm.EQ($0, $1) })
        return database[tableName, scheme].update(searchTerms, newValues: [attribute: value])
    }
    
    private func changed() {
        let value = self.get()
        if let value = value.ok {
            changeObserver(value)
        }
    }
}