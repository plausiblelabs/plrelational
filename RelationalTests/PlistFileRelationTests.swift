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
    
    func testEmptyRoundTripWithUnsetURL() {
        let r1Result = PlistFileRelation.withFile(nil, scheme: ["a"], createIfDoesntExist: true)
        XCTAssertNil(r1Result.err)
        let r1 = r1Result.ok!
        
        let r2Result = PlistFileRelation.withFile(nil, scheme: ["a"], createIfDoesntExist: true)
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
            _ = r1.add(row)
        }
        
        XCTAssertNil(r1.save().err)
        
        let r2Result = PlistFileRelation.withFile(url, scheme: r1.scheme, createIfDoesntExist: false)
        XCTAssertNil(r2Result.err)
        let r2 = r2Result.ok!
        
        AssertEqual(r1, r2)
    }
    
    func testCodec() {
        struct PrefixCodec: DataCodec {
            static let prefix = "testprefix"
            
            func encode(_ data: Data) -> Result<Data, RelationError> {
                return .Ok(PrefixCodec.prefix.utf8 + data)
            }
            
            func decode(_ data: Data) -> Result<Data, RelationError> {
                let prefixLength = Array(PrefixCodec.prefix.utf8).count
                return .Ok(Data(data[prefixLength ..< data.count]))
            }
        }
        
        let url = tmpURL()
        
        let schemeAttributes: [Attribute] = ["first", "last", "job"]
        let r1Result = PlistFileRelation.withFile(url, scheme: Scheme(attributes: Set(schemeAttributes)), createIfDoesntExist: true, codec: PrefixCodec())
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
            _ = r1.add(row)
        }
        
        XCTAssertNil(r1.save().err)
        
        let r2Result = PlistFileRelation.withFile(url, scheme: r1.scheme, createIfDoesntExist: false, codec: PrefixCodec())
        XCTAssertNil(r2Result.err)
        let r2 = r2Result.ok!
        
        AssertEqual(r1, r2)
        
        let contents = try! Data(contentsOf: url)
        XCTAssertTrue(contents.starts(with: PrefixCodec.prefix.utf8))
    }
}
