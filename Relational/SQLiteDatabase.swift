//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import sqlite3

typealias sqlite3 = COpaquePointer
typealias sqlite3_stmt = COpaquePointer

let SQLITE_TRANSIENT = unsafeBitCast(-1, sqlite3_destructor_type.self)

private struct BLOBHeaders {
    static let length = 4
    static let NULL = Array("NULL".utf8)
    static let BLOB = Array("BLOB".utf8)
}

public class SQLiteDatabase {
    let db: sqlite3
    
    private var tables = Mutexed<[String: SQLiteTableRelation]>([:])
    
    public init(_ path: String) throws {
        var localdb: sqlite3 = nil
        let result = sqlite3_open_v2(path, &localdb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        if result != SQLITE_OK {
            let message = String.fromCString(sqlite3_errstr(result))
            throw Error(code: result, message: message ?? "")
        }
        self.db = localdb
        
        try tables.withMutableValue({ $0 = try self.queryTables().orThrow() })
    }
    
    deinit {
        try! errwrap(sqlite3_close_v2(db)).orThrow()
    }
    
    private func queryTables() -> Result<[String: SQLiteTableRelation], RelationError> {
        let masterName = "SQLITE_MASTER"
        let masterScheme = schemeForTable(masterName)
        return masterScheme.then({ (scheme: Scheme) -> Result<[String: SQLiteTableRelation], RelationError> in
            let master = SQLiteTableRelation(db: self, tableName: masterName, scheme: scheme)
            let tables = master.select(Attribute("type") *== "table")
            let names = mapOk(tables.rows(), { (row: Row) -> String in row["name"].get()! as String })
            return names.then({ names in
                let schemes = names.map({ schemeForTable($0) })
                let tables = zip(names, schemes).map({ (name, scheme) in
                    scheme.map({ SQLiteTableRelation(db: self, tableName: name, scheme: $0) })
                })
                let tableDict = mapOk(tables, { ($0.tableName, $0) }).map({ Dictionary($0) })
                return tableDict
            })
        })
    }
    
    private func schemeForTable(name: String) -> Result<Scheme, RelationError> {
        let columns = executeQuery("pragma table_info(\(escapeIdentifier(name)))")
        let names = mapOk(columns, { $0["name"].get()! as String })
        return names.map({ Scheme(attributes: Set($0.map({ Attribute($0) }))) })
    }
}

extension SQLiteDatabase {
    public struct Error: ErrorType {
        public var code: Int32
        public var message: String
    }
    
    func errwrap(callResult: Int32) -> Result<Int32, RelationError> {
        switch callResult {
        case SQLITE_OK, SQLITE_ROW, SQLITE_DONE:
            return .Ok(callResult)
        default:
            let message = String.fromCString(sqlite3_errmsg(db))
            return .Err(Error(code: callResult, message: message ?? ""))
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
    public func createRelation(name: String, scheme: Scheme) -> Result<SQLiteTableRelation, RelationError> {
        let allColumns: [String]  = scheme.attributes.map({ escapeIdentifier($0.name) })
        
        let columnsSQL = allColumns.joinWithSeparator(", ")
        let sql = "CREATE TABLE IF NOT EXISTS \(escapeIdentifier(name)) (\(columnsSQL), UNIQUE (\(columnsSQL)) ON CONFLICT REPLACE)"
        
        let result = executeQuery(sql)
        return result.map({ rows in
            let array = Array(rows)
            precondition(array.isEmpty, "Unexpected result from CREATE TABLE statement: \(array)")
            
            let relation = SQLiteTableRelation(db: self, tableName: name, scheme: scheme)
            tables.withMutableValue({ $0[name] = relation })
            return relation
        })
    }
    
    public func getOrCreateRelation(name: String, scheme: Scheme) -> Result<SQLiteTableRelation, RelationError> {
        // TODO: this is not thread safe. Does it need to be?
        if let relation = self[name] {
            return .Ok(relation)
        } else {
            return createRelation(name, scheme: scheme)
        }
    }
    
    public subscript(name: String) -> SQLiteTableRelation? {
        return tables.withValue({ $0[name] })
    }
}

extension SQLiteDatabase {
    func executeQuery(sql: String, _ parameters: [RelationValue] = []) -> Result<AnyGenerator<Result<Row, RelationError>>, RelationError> {
        return makeStatement({ sqlite3_prepare_v2(self.db, sql, -1, &$0, nil) }).then({ stmt -> Result<AnyGenerator<Result<Row, RelationError>>, RelationError> in
            for (index, param) in parameters.enumerate() {
                if let err = bindValue(stmt.value, Int32(index + 1), param).err {
                    return .Err(err)
                }
            }
            
            var didError = false
            
            return .Ok(AnyGenerator(body: {
                if didError {
                    return nil
                }
                
                let result = self.errwrap(sqlite3_step(stmt.value))
                if result.err != nil {
                    didError = true
                }
                
                return result.map({ (code: Int32) -> Row? in
                    if code == SQLITE_DONE { return nil }
                    if code != SQLITE_ROW {
                        fatalError("Got a result from sqlite3_step that I don't know how to handle: \(result)")
                    }
                    
                    var row = Row(values: [:])
                    
                    let columnCount = sqlite3_column_count(stmt.value)
                    for i in 0..<columnCount {
                        let name = String.fromCString(sqlite3_column_name(stmt.value, i))
                        let value = self.columnToValue(stmt.value, i)
                        row[Attribute(name!)] = value
                    }
                    
                    return row
                })
            }))
        })
    }
    
    func executeQueryWithEmptyResults(sql: String, _ parameters: [RelationValue] = []) -> Result<Void, RelationError> {
        return executeQuery(sql, parameters).then({
            let rows = Array($0)
            if let error = rows.first?.err {
                return .Err(error)
            }
            precondition(rows.isEmpty, "Unexpected result from \(sql) query: \(rows)")
            return .Ok()
        })
    }
    
    private func columnToValue(stmt: sqlite3_stmt, _ index: Int32) -> RelationValue {
        let type = sqlite3_column_type(stmt, index)
        switch type {
        case SQLITE_NULL: return .NULL // TODO: We don't really support SQLITE_NULL. We write out our own NULLs using funky BLOBs. Is it wise to read them in?
        case SQLITE_INTEGER: return .Integer(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT: return .Real(sqlite3_column_double(stmt, index))
        case SQLITE_TEXT: return .Text(String.fromCString(UnsafePointer(sqlite3_column_text(stmt, index)))!)
        case SQLITE_BLOB:
            let ptr = UnsafePointer<UInt8>(sqlite3_column_blob(stmt, index))
            let length = sqlite3_column_bytes(stmt, index)
            let buffer = UnsafeBufferPointer<UInt8>(start: ptr, count: Int(length))
            return blobToValue(buffer)
        default:
            fatalError("Got unknown column type \(type) from SQLite")
        }
    }
    
    private func blobToValue(buffer: UnsafeBufferPointer<UInt8>) -> RelationValue {
        if buffer.count < BLOBHeaders.length { fatalError("Got a blob of length \(buffer.count) from SQLite, which isn't long enough to contain our header") }
        if memcmp(buffer.baseAddress, BLOBHeaders.NULL, BLOBHeaders.length) == 0 {
            return .NULL
        } else if memcmp(buffer.baseAddress, BLOBHeaders.BLOB, BLOBHeaders.length) == 0 {
            let remainder = buffer.suffixFrom(BLOBHeaders.length)
            return .Blob(Array(remainder))
        } else {
            preconditionFailure("Got a blob with a header prefix \(buffer.prefix(4)) which we don't understand.")
        }
    }
    
    private func bindValue(stmt: sqlite3_stmt, _ index: Int32, _ value: RelationValue) -> Result<Void, RelationError> {
        let result: Result<Int32, RelationError>
        switch value {
        case .NULL: result = self.errwrap(sqlite3_bind_blob64(stmt, index, BLOBHeaders.NULL, UInt64(BLOBHeaders.length), SQLITE_TRANSIENT))
        case .Integer(let x): result = self.errwrap(sqlite3_bind_int64(stmt, index, x))
        case .Real(let x): result = self.errwrap(sqlite3_bind_double(stmt, index, x))
        case .Text(let x): result = self.errwrap(sqlite3_bind_text(stmt, index, x, -1, SQLITE_TRANSIENT))
        case .Blob(let x): result = self.errwrap(sqlite3_bind_blob64(stmt, index, BLOBHeaders.BLOB + x, UInt64(BLOBHeaders.length + x.count), SQLITE_TRANSIENT))
        case .NotFound: result = .Ok(0)
        }
        return result.map({ _ in })
    }
}

extension SQLiteDatabase {
    func makeStatement(@noescape sqliteCall: (inout sqlite3_stmt) -> Int32) -> Result<ValueWithDestructor<sqlite3_stmt>, RelationError> {
        var localStmt: sqlite3_stmt = nil
        return errwrap(sqliteCall(&localStmt)).map({ _ in
            ValueWithDestructor(value: localStmt, destructor: {
                // Note: sqlite3_finalize can return errors, but it only returns an error
                // when the most recent evaluation of the statement produced an error, in
                // which case _finalize just returns that same error again. So the only
                // time _finalize will return an error is if we've already seen (and handled)
                // that error elsewhere, and we can (and want to) ignore it here.
                sqlite3_finalize($0)
            })
        })
    }
}

extension SQLiteDatabase {
    public enum TransactionResult {
        case Commit
        case Rollback
    }
    
    public func transaction<Return>(@noescape transactionFunction: Void -> (Return, TransactionResult)) -> Result<Return, RelationError> {
        // TODO: it might make sense to pass a new DB into the object, but in fact changes affect the original database object.
        // This will matter if the caller tries to access the original database during the transaction and expects it not to
        // reflect the new changes.
        // TODO TOO: we'd want to retry on failed commits in some cases, and give the callee the ability to rollback.
        return executeQueryWithEmptyResults("BEGIN TRANSACTION").then({
            let result = transactionFunction()
            let sql: String
            switch result.1 {
            case .Commit: sql = "COMMIT TRANSACTION"
            case .Rollback: sql = "ROLLBACK TRANSACTION"
            }
            return self.executeQueryWithEmptyResults(sql).map({ result.0 })
        })
    }
    
    public func transaction(@noescape transactionFunction: Void -> TransactionResult) -> Result<Void, RelationError> {
        return self.transaction({ Void -> ((), TransactionResult) in
            let result = transactionFunction()
            return ((), result)
        })
    }
}
