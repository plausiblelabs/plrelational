
import sqlite3

class SQLiteRelation: Relation {
    let db: SQLiteDatabase
    let tableName: String
    
    var tableNameForQuery: String {
        return db.escapeIdentifier(tableName)
    }
    
    init(db: SQLiteDatabase, tableName: String) {
        self.db = db
        self.tableName = tableName
    }
    
    var scheme: Scheme {
        fatalError("unimplemented")
    }
    
    func rows() -> AnyGenerator<Row> {
        fatalError("unimplemented")
    }
    
    func contains(row: Row) -> Bool {
        fatalError("unimplemented")
    }
}

extension SQLiteRelation {
    func add(row: Row) throws {
        let orderedAttributes = Array(row.values.keys)
        let attributesSQL = orderedAttributes.map({ db.escapeIdentifier($0.name) }).joinWithSeparator(", ")
        let valuesSQL = Array(count: orderedAttributes.count, repeatedValue: "?").joinWithSeparator(", ")
        let sql = "INSERT INTO \(tableNameForQuery) (\(attributesSQL)) VALUES (\(valuesSQL))"
        
        var stmt: sqlite3_stmt = nil
        try db.errwrap(sqlite3_prepare_v2(db.db, sql, -1, &stmt, nil))
        defer { try! db.errwrap(sqlite3_finalize(stmt)) }
        
        for (index, attribute) in orderedAttributes.enumerate() {
            try db.errwrap(sqlite3_bind_text(stmt, Int32(index + 1), row[attribute], -1, SQLITE_TRANSIENT))
        }
        
        let result = try db.errwrap(sqlite3_step(stmt))
        if result != SQLITE_DONE {
            throw SQLiteDatabase.Error(code: result, message: "Unexpected non-error result stepping INSERT INTO statement: \(result)")
        }
    }
    
    func delete(row: Row) {
        fatalError("unimplemented")
    }
    
    func change(rowToFind: Row, to: Row) {
        fatalError("unimplemented")
    }
}
