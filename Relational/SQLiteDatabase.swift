
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
        
        tables = try self.queryTables().orThrow()
    }
    
    deinit {
        try! errwrap(sqlite3_close_v2(db)).orThrow()
    }
    
    private func queryTables() -> Result<Set<String>, RelationError> {
        let masterName = "SQLITE_MASTER"
        let masterScheme = schemeForTable(masterName)
        return masterScheme.then({ (scheme: Scheme) -> Result<Set<String>, RelationError> in
            let master = self[masterName, scheme]
            let tables = master.select([.EQ(Attribute("type"), "table")])
            let names = mapOk(tables.rows(), { (row: Row) -> String in row["name"].get()! as String })
            return names.map({ Set($0) })
        })
    }
    
    private func schemeForTable(name: String) -> Result<Scheme, RelationError> {
        let columns = executeQuery("pragma table_info(\(escapeIdentifier(name)))")
        let names = mapOk(columns, { $0["name"].get()! as String })
        return names.map({ Scheme(attributes: Set($0.map({ Attribute($0) }))) })
    }
}

extension SQLiteDatabase {
    struct Error: ErrorType {
        var code: Int32
        var message: String
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
    func createRelation(name: String, scheme: Scheme) -> Result<Void, RelationError> {
        let allColumns: [String]  = scheme.attributes.map({ escapeIdentifier($0.name) })
        
        let columnsSQL = allColumns.joinWithSeparator(", ")
        let sql = "CREATE TABLE IF NOT EXISTS \(escapeIdentifier(name)) (\(columnsSQL))"
        
        let result = executeQuery(sql)
        return result.map({ rows in
            let array = Array(rows)
            precondition(array.isEmpty, "Unexpected result from CREATE TABLE statement: \(array)")
            tables.insert(name)
            return ()
        })
    }
    
    subscript(name: String, scheme: Scheme) -> SQLiteTableRelation {
        return SQLiteTableRelation(db: self, tableName: name, scheme: scheme)
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
            
            return .Ok(AnyGenerator(body: {
                let result = self.errwrap(sqlite3_step(stmt.value))
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
    
    private func bindValue(stmt: sqlite3_stmt, _ index: Int32, _ value: RelationValue) -> Result<Void, RelationError> {
        let result: Result<Int32, RelationError>
        switch value {
        case .NULL: result = self.errwrap(sqlite3_bind_null(stmt, index))
        case .Integer(let x): result =  self.errwrap(sqlite3_bind_int64(stmt, index, x))
        case .Real(let x): result =  self.errwrap(sqlite3_bind_double(stmt, index, x))
        case .Text(let x): result =  self.errwrap(sqlite3_bind_text(stmt, index, x, -1, SQLITE_TRANSIENT))
        case .Blob(let x): result =  self.errwrap(sqlite3_bind_blob64(stmt, index, x, UInt64(x.count), SQLITE_TRANSIENT))
        }
        return result.map({ _ in })
    }
}

extension SQLiteDatabase {
    func makeStatement(@noescape sqliteCall: (inout sqlite3_stmt) -> Int32) -> Result<ValueWithDestructor<sqlite3_stmt>, RelationError> {
        var localStmt: sqlite3_stmt = nil
        return errwrap(sqliteCall(&localStmt)).map({ _ in
            ValueWithDestructor(value: localStmt, destructor: {
                // TODO: handle errors somehow?
                sqlite3_finalize($0)
            })
        })
    }
}
