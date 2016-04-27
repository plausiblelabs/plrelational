
import XCTest
import libRelational

class RelationalTests: XCTestCase {
    var dbPaths: [String] = []
    
    override func tearDown() {
        for path in dbPaths {
            _ = try? NSFileManager.defaultManager().removeItemAtPath(path)
        }
    }
    
    func makeDB() -> (path: String, db: ModelDatabase) {
        let tmp = NSTemporaryDirectory() as NSString
        let dbname = "testing-\(NSUUID()).db"
        let path = tmp.stringByAppendingPathComponent(dbname)
        
        let sqlite = try! SQLiteDatabase(path)
        let db = ModelDatabase(sqlite)
        
        dbPaths.append(path)
        
        return (path, db)
    }
    
    func testLib() {
        let db = makeDB().db
        XCTAssertEqual(db.sqliteDatabase.tables, [])
        
        let store = Store(owningDatabase: db, name: "Joe's")
        XCTAssertNotNil(db.add(store).ok)
        
        let store2 = db.fetchAll(Store.self).generate().next()!.ok!
        XCTAssertEqual(store2.name, "Joe's")
    }
}
