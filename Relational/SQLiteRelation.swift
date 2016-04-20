
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
        let columns = try! query("pragma table_info(\(tableNameForQuery))")
        return Scheme(attributes: Set(columns.map({ Attribute($0["name"]) })))
    }
    
    func rows() -> AnyGenerator<Row> {
        return try! query("SELECT * FROM \(tableNameForQuery)")
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
        
        let stmt = try SQLiteStatement(sqliteCall: { try db.errwrap(sqlite3_prepare_v2(db.db, sql, -1, &$0, nil)) })
        
        for (index, attribute) in orderedAttributes.enumerate() {
            try db.errwrap(sqlite3_bind_text(stmt.stmt, Int32(index + 1), row[attribute], -1, SQLITE_TRANSIENT))
        }
        
        let result = try db.errwrap(sqlite3_step(stmt.stmt))
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

extension SQLiteRelation {
    func query(sql: String, _ parameters: [String] = []) throws -> AnyGenerator<Row> {
        let stmt = try SQLiteStatement(sqliteCall: { try db.errwrap(sqlite3_prepare_v2(db.db, sql, -1, &$0, nil)) })
        for (index, param) in parameters.enumerate() {
            try db.errwrap(sqlite3_bind_text(stmt.stmt, Int32(index + 1), param, -1, SQLITE_TRANSIENT))
        }
        
        return AnyGenerator(body: {
            let result = sqlite3_step(stmt.stmt)
            if result == SQLITE_DONE { return nil }
            if result != SQLITE_ROW {
                fatalError("Got a result from sqlite3_step that I don't know how to handle: \(result)")
            }
            
            var row = Row(values: [:])
            
            let columnCount = sqlite3_column_count(stmt.stmt)
            for i in 0..<columnCount {
                let name = String.fromCString(sqlite3_column_name(stmt.stmt, i))
                let value = String.fromCString(UnsafePointer(sqlite3_column_text(stmt.stmt, i)))
                if let value = value {
                    row[Attribute(name!)] = value
                }
            }
            
            return row
        })
    }
}
