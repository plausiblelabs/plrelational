//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import PLRelationalCombine

class CombineTestCase: XCTestCase {
    
    var dbPaths: [String] = []
    
    override func tearDown() {
        for path in dbPaths {
            _ = try? FileManager.default.removeItem(atPath: path)
        }
    }
    
    func makeDB() -> (path: String, db: SQLiteDatabase) {
        let tmp = NSTemporaryDirectory() as NSString
        let dbname = "testing-\(UUID()).db"
        let path = tmp.appendingPathComponent(dbname)
        _ = try? FileManager.default.removeItem(atPath: path)
        
        Swift.print("Creating SQLite database at \(path)")
        let db = try! SQLiteDatabase(path)
        
        dbPaths.append(path)
        
        return (path, db)
    }

    /// Synchronously waits for AsyncManager to process the given work and return to an `idle` state.
    func awaitCompletion(_ f: () -> Void) {
        f()
        awaitIdle()
    }
    
    /// Synchronously waits for AsyncManager to return to an `idle` state.
    func awaitIdle() {
        Async.awaitAsyncCompletion()
    }
}
