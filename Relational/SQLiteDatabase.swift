
import sqlite3

typealias sqlite3 = COpaquePointer
typealias sqlite3_stmt = COpaquePointer

let SQLITE_TRANSIENT = unsafeBitCast(-1, sqlite3_destructor_type.self)

class SQLiteDatabase {
    let db: sqlite3
    
    init(_ path: String) throws {
        var localdb: sqlite3 = nil
        let result = sqlite3_open_v2(path, &localdb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        if result != SQLITE_OK {
            let message = String.fromCString(sqlite3_errstr(result))
            throw Error(code: result, message: message ?? "")
        }
        self.db = localdb
    }
    
    deinit {
        try! errwrap(sqlite3_close_v2(db))
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
        let columns = scheme.attributes.map({ escapeIdentifier($0.name) }).joinWithSeparator(", ")
        let sql = "CREATE TABLE \(escapeIdentifier(name)) (\(columns))"
        
        var stmt: sqlite3_stmt = nil
        try errwrap(sqlite3_prepare_v2(db, sql, -1, &stmt, nil))
        defer { try! errwrap(sqlite3_finalize(stmt)) }
        
        let result = try errwrap(sqlite3_step(stmt))
        if result != SQLITE_DONE {
            throw Error(code: result, message: "Unexpected non-error result stepping CREATE TABLE statement: \(result)")
        }
    }
    
    subscript(name: String) -> SQLiteRelation {
        return SQLiteRelation(db: self, tableName: name)
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
