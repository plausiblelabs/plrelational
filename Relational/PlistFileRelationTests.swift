//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


import XCTest
import libRelational

class PlistFileRelationTests: XCTestCase {
    var urls: [URL] = []
    
    override func tearDown() {
        super.tearDown()
        
        for url in urls {
            _ = try? FileManager.default.removeItem(at: url)
        }
        urls = []
    }
    
    func tmpURL() -> URL {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let url = tmp.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        urls.append(url)
        return url
    }
    
    func testErrorOnNonexistentFile() {
        let result = PlistFileRelation.withFile(tmpURL(), scheme: ["a"], createIfDoesntExist: false)
        XCTAssertNotNil(result.err)
    }
    
    func testEmptyRoundTrip() {
        let url = tmpURL()
        
        let r1Result = PlistFileRelation.withFile(url, scheme: ["a"], createIfDoesntExist: true)
        XCTAssertNil(r1Result.err)
        let r1 = r1Result.ok!
        
        XCTAssertNil(r1.save().err)
        
        let r2Result = PlistFileRelation.withFile(url, scheme: ["a"], createIfDoesntExist: true)
        XCTAssertNil(r2Result.err)
        let r2 = r2Result.ok!
        
        AssertEqual(r1, r2)
    }
    
    func testDataRoundTrip() {
        let url = tmpURL()
        
        let schemeAttributes: [Attribute] = ["first", "last", "job"]
        let r1Result = PlistFileRelation.withFile(url, scheme: Scheme(attributes: Set(schemeAttributes)), createIfDoesntExist: true)
        XCTAssertNil(r1Result.err)
        let r1 = r1Result.ok!
        
        let testRowValues: [[RelationValue]] = [
            ["Steve", "Jobs", "CEO"],
            ["Bob", "Dole", "Senator"],
            ["Tim", "Allen", "Pharmacist"],
            ["Steven", "Tyler", "Musician"],
            [.null, 42, 666.0],
            [0, 0, RelationValue.blob([1, 2, 3, 4, 5])]
        ]
        
        for rowValues in testRowValues {
            let row = Row(values: Dictionary(zip(schemeAttributes, rowValues)))
            r1.add(row)
        }
        
        XCTAssertNil(r1.save().err)
        
        let r2Result = PlistFileRelation.withFile(url, scheme: r1.scheme, createIfDoesntExist: true)
        XCTAssertNil(r2Result.err)
        let r2 = r2Result.ok!
        
        AssertEqual(r1, r2)
    }
}
