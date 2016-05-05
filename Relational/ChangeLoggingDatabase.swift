
public class ChangeLoggingDatabase {
    let sqliteDatabase: SQLiteDatabase
    
    var changeLoggingRelations: [String: ChangeLoggingRelation<SQLiteTableRelation>] = [:]
    
    public init(_ db: SQLiteDatabase) {
        self.sqliteDatabase = db
    }
    
    public func createRelation(name: String, scheme: Scheme) -> Result<Void, RelationError> {
        return sqliteDatabase.createRelation(name, scheme: scheme)
    }
    
    public subscript(name: String, scheme: Scheme) -> ChangeLoggingRelation<SQLiteTableRelation> {
        if let relation = changeLoggingRelations[name] {
            return relation
        } else {
            let table = sqliteDatabase[name, scheme]
            let relation = ChangeLoggingRelation(underlyingRelation: table)
            changeLoggingRelations[name] = relation
            return relation
        }
    }
    
    public func save() -> Result<Void, RelationError> {
        // TODO: transactions!
        for (_, relation) in changeLoggingRelations {
            let result = relation.save()
            if let err = result.err {
                return .Err(err)
            }
        }
        return .Ok()
    }
}
