
import XCTest
import libRelational

func AssertEqual(a: Relation?, _ b: Relation?, file: StaticString = #file, line: UInt = #line) {
    guard let a = a else {
        guard let b = b else { return }
        XCTAssertTrue(b.isEmpty.ok == true, "First relation is nil, second relation is not nil and not empty:\n\(b)", file: file, line: line)
        return
    }
    guard let b = b else {
        XCTAssertTrue(a.isEmpty.ok == true, "Second relation is nil, first relation is not nil and not empty:\n\(a)", file: file, line: line)
        return
    }
    XCTAssertEqual(a.scheme, b.scheme, "Relation schemes are not equal", file: file, line: line)
    let aRows = mapOk(a.rows(), { $0 })
    let bRows = mapOk(b.rows(), { $0 })
    
    switch (aRows, bRows) {
    case (.Ok(let aRows), .Ok(let bRows)):
        let aSet = Set(aRows)
        let bSet = Set(bRows)
        XCTAssertEqual(aSet, bSet, "Relations are not equal but should be. First relation:\n\(a)\n\nSecond relation:\n\(b)", file: file, line: line)
    default:
        XCTAssertNil(aRows.err)
        XCTAssertNil(bRows.err)
    }
}

func AssertEqual<M1: Model, M2: Model, Seq: SequenceType where Seq.Generator.Element == Result<M1, RelationError>>(a: Seq, _ b: [M2], file: StaticString = #file, line: UInt = #line) {
    let aRows = mapOk(a, { $0.toRow() })
    let bRows = b.map({ $0.toRow() })
    
    XCTAssertNil(aRows.err, file: file, line: line)
    aRows.map({
        XCTAssertEqual(Set($0), Set(bRows), file: file, line: line)
    })
}

class DBTestCase: XCTestCase {
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
}
