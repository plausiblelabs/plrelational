
import sqlite3

typealias sqlite3 = COpaquePointer
typealias sqlite3_stmt = COpaquePointer

let SQLITE_TRANSIENT = unsafeBitCast(-1, sqlite3_destructor_type.self)

class SQLiteDatabase {
    let db: sqlite3
    
    var tables: Set<String> = []
    
    init(_ path: String) throws {
        var localdb: sqlite3 = nil
        let result = sqlite3_open_v2(path, &localdb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        if result != SQLITE_OK {
            let message = String.fromCString(sqlite3_errstr(result))
            throw Error(code: result, message: message ?? "")
        }
        self.db = localdb
        
        tables = try self.queryTables()
    }
    
    deinit {
        try! errwrap(sqlite3_close_v2(db))
    }
    
    private func queryTables() throws -> Set<String> {
        let masterName = "SQLITE_MASTER"
        let masterScheme = try schemeForTable(masterName)
        let master = self[masterName, masterScheme]
        let tables = master.select([.EQ(Attribute("type"), "table")])
        let names = tables.rows().map({ $0["name"] })
        return Set(names.map({ $0.get()! }))
    }
    
    private func schemeForTable(name: String) throws -> Scheme {
        let columns = try executeQuery("pragma table_info(\(escapeIdentifier(name)))")
        return Scheme(attributes: Set(columns.map({ Attribute($0["name"].get()!) })))
    }
}

extension SQLiteDatabase {
    struct Error: ErrorType {
        var code: Int32
        var message: String
    }
    
    func errwrap(callResult: Int32) throws -> Int32 {
        switch callResult {
        case SQLITE_OK, SQLITE_ROW, SQLITE_DONE:
            return callResult
        default:
            let message = String.fromCString(sqlite3_errmsg(db))
            throw Error(code: callResult, message: message ?? "")
        }
    }
}

extension SQLiteDatabase {
    func escapeIdentifier(id: String) -> String {
        let escapedQuotes = id.stringByReplacingOccurrencesOfString("\"", withString: "\"\"")
        return "\"\(escapedQuotes)\""
    }
}

extension SQLiteDatabase {
    func createRelation(name: String, scheme: Scheme) throws {
        let allColumns: [String]  = scheme.attributes.map({ escapeIdentifier($0.name) })
        
        let columnsSQL = allColumns.joinWithSeparator(", ")
        let sql = "CREATE TABLE IF NOT EXISTS \(escapeIdentifier(name)) (\(columnsSQL))"
        
        var stmt: sqlite3_stmt = nil
        try errwrap(sqlite3_prepare_v2(db, sql, -1, &stmt, nil))
        defer { try! errwrap(sqlite3_finalize(stmt)) }
        
        let result = try errwrap(sqlite3_step(stmt))
        if result != SQLITE_DONE {
            throw Error(code: result, message: "Unexpected non-error result stepping CREATE TABLE statement: \(result)")
        }
        
        tables.insert(name)
    }
    
    subscript(name: String, scheme: Scheme) -> SQLiteTableRelation {
        return SQLiteTableRelation(db: self, tableName: name, scheme: scheme)
    }
}

extension SQLiteDatabase {
    func executeQuery(sql: String, _ parameters: [RelationValue] = []) throws -> AnyGenerator<Row> {
        let stmt = try SQLiteStatement(sqliteCall: { try self.errwrap(sqlite3_prepare_v2(self.db, sql, -1, &$0, nil)) })
        for (index, param) in parameters.enumerate() {
            try self.bindValue(stmt.stmt, Int32(index + 1), param)
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
                let value = self.columnToValue(stmt.stmt, i)
                row[Attribute(name!)] = value
            }
            
            return row
        })
    }
    
    private func columnToValue(stmt: sqlite3_stmt, _ index: Int32) -> RelationValue {
        let type = sqlite3_column_type(stmt, index)
        switch type {
        case SQLITE_NULL: return .NULL
        case SQLITE_INTEGER: return .Integer(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT: return .Real(sqlite3_column_double(stmt, index))
        case SQLITE_TEXT: return .Text(String.fromCString(UnsafePointer(sqlite3_column_text(stmt, index)))!)
        case SQLITE_BLOB:
            let ptr = UnsafePointer<UInt8>(sqlite3_column_blob(stmt, index))
            let length = sqlite3_column_bytes(stmt, index)
            let buffer = UnsafeBufferPointer<UInt8>(start: ptr, count: Int(length))
            return .Blob(Array(buffer))
        default:
            fatalError("Got unknown column type \(type) from SQLite")
        }
    }
    
    private func bindValue(stmt: sqlite3_stmt, _ index: Int32, _ value: RelationValue) throws {
        switch value {
        case .NULL: try self.errwrap(sqlite3_bind_null(stmt, index))
        case .Integer(let x): try self.errwrap(sqlite3_bind_int64(stmt, index, x))
        case .Real(let x): try self.errwrap(sqlite3_bind_double(stmt, index, x))
        case .Text(let x): try self.errwrap(sqlite3_bind_text(stmt, index, x, -1, SQLITE_TRANSIENT))
        case .Blob(let x): try self.errwrap(sqlite3_bind_blob64(stmt, index, x, UInt64(x.count), SQLITE_TRANSIENT))
        }
    }
}

class SQLiteStatement {
    let stmt: sqlite3_stmt
    
    init(@noescape sqliteCall: (inout sqlite3_stmt) throws -> Void) rethrows {
        var localStmt: sqlite3_stmt = nil
        try sqliteCall(&localStmt)
        self.stmt = localStmt
    }
    
    deinit {
        sqlite3_finalize(stmt)
    }
}
