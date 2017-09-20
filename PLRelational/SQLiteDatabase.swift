//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import sqlite3

public typealias sqlite3 = OpaquePointer
typealias sqlite3_stmt = OpaquePointer

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private let busyTimeout: Int32 = 10 // milliseconds

private struct BLOBHeaders {
    static let length = 4
    static let NULL = Array("NULL".utf8)
    static let BLOB = Array("BLOB".utf8)
}

open class SQLiteDatabase: StoredDatabase {
    public let db: sqlite3
    
    fileprivate var tables = Mutexed<[String: SQLiteTableRelation]>([:])
    
    public init(_ path: String) throws {
        var localdb: sqlite3? = nil
        let result = sqlite3_open_v2(path, &localdb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        if result != SQLITE_OK {
            let message = String(cString: sqlite3_errstr(result))
            throw Error(code: result, message: message)
        }
        self.db = localdb!
        
        _ = try errwrap(sqlite3_busy_timeout(self.db, busyTimeout)).orThrow()
        
        try tables.withMutableValue({ $0 = try self.queryTables().orThrow() })
    }
    
    deinit {
        _ = try! errwrap(sqlite3_close_v2(db)).orThrow()
    }
    
    fileprivate func queryTables() -> Result<[String: SQLiteTableRelation], RelationError> {
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
    
    fileprivate func schemeForTable(_ name: String) -> Result<Scheme, RelationError> {
        let columns = executeQuery("pragma table_info(\(escapeIdentifier(name)))")
        let names = mapOk(columns, { $0["name"].get()! as String })
        return names.map({ Scheme(attributes: Set($0.map({ Attribute($0) }))) })
    }
}

extension SQLiteDatabase {
    public struct Error: Swift.Error {
        public var code: Int32
        public var message: String
    }
    
    func errwrap(_ callResult: Int32) -> Result<Int32, RelationError> {
        switch callResult {
        case SQLITE_OK, SQLITE_ROW, SQLITE_DONE:
            return .Ok(callResult)
        default:
            let message = String(cString: sqlite3_errmsg(db))
            return .Err(Error(code: callResult, message: message))
        }
    }
}

extension SQLiteDatabase {
    public func escapeIdentifier(_ id: String) -> String {
        let escapedQuotes = id.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escapedQuotes)\""
    }
}

extension SQLiteDatabase {
    public func createRelation(_ name: String, scheme: Scheme) -> Result<SQLiteTableRelation, RelationError> {
        let allColumns: [String]  = scheme.attributes.map({ escapeIdentifier($0.name) })
        
        let columnsSQL = allColumns.joined(separator: ", ")
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
    
    public func getOrCreateRelation(_ name: String, scheme: Scheme) -> Result<SQLiteTableRelation, RelationError> {
        // TODO: this is not thread safe. Does it need to be?
        if let relation = self[name] {
            return .Ok(relation)
        } else {
            return createRelation(name, scheme: scheme)
        }
    }
    
    private func table(forName name: String) -> SQLiteTableRelation? {
        return tables.withValue({ $0[name] })
    }

    public func storedRelation(forName name: String) -> StoredRelation? {
        return table(forName: name)
    }
    
    public subscript(name: String) -> SQLiteTableRelation? {
        return table(forName: name)
    }
}

extension SQLiteDatabase {
    public func executeQuery(_ sql: String, _ parameters: [RelationValue] = [], bindBlobsRaw: Bool = false) -> Result<AnyIterator<Result<Row, RelationError>>, RelationError> {
        return makeStatement({ sqlite3_prepare_v2(self.db, sql, -1, &$0, nil) }).then({ stmt -> Result<AnyIterator<Result<Row, RelationError>>, RelationError> in
            for (index, param) in parameters.enumerated() {
                if let err = bindValue(stmt.value, Int32(index + 1), param, bindBlobsRaw: bindBlobsRaw).err {
                    return .Err(err)
                }
            }
            
            var didError = false
            
            return .Ok(AnyIterator({
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
                        let name = String(cString: sqlite3_column_name(stmt.value, i))
                        let value = self.columnToValue(stmt.value, i, rawBlobs: bindBlobsRaw)
                        row[Attribute(name)] = value
                    }
                    
                    return row
                })
            }))
        })
    }
    
    public func executeQueryWithEmptyResults(_ sql: String, _ parameters: [RelationValue] = [], bindBlobsRaw: Bool = false) -> Result<Void, RelationError> {
        return executeQuery(sql, parameters, bindBlobsRaw: bindBlobsRaw).then({
            let rows = Array($0)
            if let error = rows.first?.err {
                return .Err(error)
            }
            precondition(rows.isEmpty, "Unexpected result from \(sql) query: \(rows)")
            return .Ok(())
        })
    }
    
    public func lastInsertRowID() -> Int64 {
        return sqlite3_last_insert_rowid(db)
    }
    
    fileprivate func columnToValue(_ stmt: sqlite3_stmt, _ index: Int32, rawBlobs: Bool) -> RelationValue {
        let type = sqlite3_column_type(stmt, index)
        switch type {
        case SQLITE_NULL: return .null // TODO: We don't really support SQLITE_NULL. We write out our own NULLs using funky BLOBs. Is it wise to read them in?
        case SQLITE_INTEGER: return .integer(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT: return .real(sqlite3_column_double(stmt, index))
        case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(stmt, index)))
        case SQLITE_BLOB:
            let length = sqlite3_column_bytes(stmt, index)
            let ptr = sqlite3_column_blob(stmt, index).bindMemory(to: UInt8.self, capacity: Int(length))
            let buffer = UnsafeBufferPointer<UInt8>(start: ptr, count: Int(length))
            return rawBlobs ? .blob(Array(buffer)) : blobToValue(buffer)
        default:
            fatalError("Got unknown column type \(type) from SQLite")
        }
    }
    
    fileprivate func blobToValue(_ buffer: UnsafeBufferPointer<UInt8>) -> RelationValue {
        if buffer.count < BLOBHeaders.length { fatalError("Got a blob of length \(buffer.count) from SQLite, which isn't long enough to contain our header") }
        if memcmp(buffer.baseAddress, BLOBHeaders.NULL, BLOBHeaders.length) == 0 {
            return .null
        } else if memcmp(buffer.baseAddress, BLOBHeaders.BLOB, BLOBHeaders.length) == 0 {
            let remainder = buffer.suffix(from: BLOBHeaders.length)
            return .blob(Array(remainder))
        } else {
            preconditionFailure("Got a blob with a header prefix \(buffer.prefix(4)) which we don't understand.")
        }
    }
    
    fileprivate func bindValue(_ stmt: sqlite3_stmt, _ index: Int32, _ value: RelationValue, bindBlobsRaw: Bool) -> Result<Void, RelationError> {
        let result: Result<Int32, RelationError>
        switch value {
        case .null: result = self.errwrap(sqlite3_bind_blob64(stmt, index, BLOBHeaders.NULL, UInt64(BLOBHeaders.length), SQLITE_TRANSIENT))
        case .integer(let x): result = self.errwrap(sqlite3_bind_int64(stmt, index, x))
        case .real(let x): result = self.errwrap(sqlite3_bind_double(stmt, index, x))
        case .text(let x): result = self.errwrap(sqlite3_bind_text(stmt, index, x, -1, SQLITE_TRANSIENT))
        case .blob(let x):
            if bindBlobsRaw {
                result = self.errwrap(sqlite3_bind_blob64(stmt, index, x, UInt64(x.count), SQLITE_TRANSIENT))
            } else {
                result = self.errwrap(sqlite3_bind_blob64(stmt, index, BLOBHeaders.BLOB + x, UInt64(BLOBHeaders.length + x.count), SQLITE_TRANSIENT))
            }
        case .notFound: result = .Ok(0)
        }
        return result.map({ _ in })
    }
}

extension SQLiteDatabase {
    func makeStatement(_ sqliteCall: (inout sqlite3_stmt?) -> Int32) -> Result<ValueWithDestructor<sqlite3_stmt>, RelationError> {
        var localStmt: sqlite3_stmt? = nil
        return errwrap(sqliteCall(&localStmt)).map({ _ in
            ValueWithDestructor(value: localStmt!, destructor: {
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
    public func transaction<Return>(_ transactionFunction: () -> (Return, TransactionResult)) -> Result<Return, RelationError> {
        // TODO: it might make sense to pass a new DB into the object, but in fact changes affect the original database object.
        // This will matter if the caller tries to access the original database during the transaction and expects it not to
        // reflect the new changes.
        // TODO TOO: we'd want to retry on failed commits in some cases, and give the callee the ability to rollback.
        var result: Result<Return, RelationError>
        var retry: Bool
        
        repeat {
            retry = false
            result = executeQueryWithEmptyResults("BEGIN TRANSACTION").then({
                let result = transactionFunction()
                let sql: String
                switch result.1 {
                case .commit: sql = "COMMIT TRANSACTION"
                case .rollback: sql = "ROLLBACK TRANSACTION"
                    
                case .retry:
                    sql = "ROLLBACK TRANSACTION"
                    retry = true
                }
                return self.executeQueryWithEmptyResults(sql).map({ result.0 })
            })
        } while retry
        
        return result
    }
    
    public func transaction(_ transactionFunction: () -> TransactionResult) -> Result<Void, RelationError> {
        return self.transaction({ () -> ((), TransactionResult) in
            let result = transactionFunction()
            return ((), result)
        })
    }
    
    public func resultNeedsRetry<T>(_ result: Result<T, RelationError>) -> Bool {
        return (result.err as? SQLiteDatabase.Error)?.code == SQLITE_BUSY
    }
}
