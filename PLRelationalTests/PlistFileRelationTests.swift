//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


import XCTest
import PLRelational

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
        let result = PlistFileRelation.withFile(tmpURL(), scheme: ["a"], primaryKeys: ["a"], create: false)
        XCTAssertNotNil(result.err)
    }
    
    func testEmptyRoundTrip() {
        let url = tmpURL()
        
        let r1Result = PlistFileRelation.withFile(url, scheme: ["a"], primaryKeys: ["a"], create: true)
        XCTAssertNil(r1Result.err)
        let r1 = r1Result.ok!
        
        XCTAssertNil(r1.save().err)
        
        let r2Result = PlistFileRelation.withFile(url, scheme: ["a"], primaryKeys: ["a"], create: true)
        XCTAssertNil(r2Result.err)
        let r2 = r2Result.ok!
        
        AssertEqual(r1, r2)
    }
    
    func testEmptyRoundTripWithUnsetURL() {
        let r1Result = PlistFileRelation.withFile(nil, scheme: ["a"], primaryKeys: ["a"], create: true)
        XCTAssertNil(r1Result.err)
        let r1 = r1Result.ok!
        
        let r2Result = PlistFileRelation.withFile(nil, scheme: ["a"], primaryKeys: ["a"], create: true)
        XCTAssertNil(r2Result.err)
        let r2 = r2Result.ok!
        
        AssertEqual(r1, r2)
    }
    
    func testDataRoundTrip() {
        let url = tmpURL()
        
        let schemeAttributes: [Attribute] = ["first", "last", "job"]
        let r1Result = PlistFileRelation.withFile(url, scheme: Scheme(attributes: Set(schemeAttributes)), primaryKeys: [], create: true)
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
        
        let r2Result = PlistFileRelation.withFile(url, scheme: r1.scheme, primaryKeys: [], create: false)
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
        let r1Result = PlistFileRelation.withFile(url, scheme: Scheme(attributes: Set(schemeAttributes)), primaryKeys: [], create: true, codec: PrefixCodec())
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
        
        let r2Result = PlistFileRelation.withFile(url, scheme: r1.scheme, primaryKeys: [], create: false, codec: PrefixCodec())
        XCTAssertNil(r2Result.err)
        let r2 = r2Result.ok!
        
        AssertEqual(r1, r2)
        
        let contents = try! Data(contentsOf: url)
        XCTAssertTrue(contents.starts(with: PrefixCodec.prefix.utf8))
    }
    
    func testSchemeMismatch() {
        let url = tmpURL()
        let r1Result = PlistFileRelation.withFile(url, scheme: ["n"], primaryKeys: [], create: true)
        XCTAssertNil(r1Result.err)
        
        XCTAssertNil(r1Result.ok?.add(["n": 1]).err)
        XCTAssertNil(r1Result.ok?.save().err)
        
        let r2Result = PlistFileRelation.withFile(url, scheme: ["m"], primaryKeys: [], create: false)
        XCTAssertNotNil(r2Result.err)
    }
    
    func testInsertPerformance() {
        let r = PlistFileRelation.withFile(nil, scheme: ["a", "b"], primaryKeys: ["a"], create: true).ok!
        
        let max: Int64 = 1000
        
        measure {
            for i in 0 ..< max {
                _ = r.add(["a": RelationValue(i), "b": RelationValue(-i)])
            }
        }
    }
    
    func testSelectPerformance() {
        let r = PlistFileRelation.withFile(nil, scheme: ["a", "b"], primaryKeys: ["a"], create: true).ok!
        
        let max: Int64 = 1000
        
        for i in 0 ..< max {
            _ = r.add(["a": RelationValue(i), "b": RelationValue(-i)])
        }
        
        measure({
            for i in 0 ..< max {
                let rows = r.select(Attribute("a") *== RelationValue(i)).rows()
                XCTAssertEqual(Array(rows).count, 1)
            }
        })
    }
    
    func testUpdatePerformance() {
        let r = PlistFileRelation.withFile(nil, scheme: ["a", "b"], primaryKeys: ["a"], create: true).ok!
        
        let max: Int64 = 1000
        
        for i in 0 ..< max {
            _ = r.add(["a": RelationValue(i), "b": RelationValue(-i)])
        }
        measure({
            for i in 0 ..< max {
                _ = r.update(Attribute("a") *== RelationValue(i), newValues: ["b": RelationValue(-i - 1)])
            }
        })
    }
    
    func testDeletePerformance() {
        let r = PlistFileRelation.withFile(nil, scheme: ["a", "b"], primaryKeys: ["a"], create: true).ok!
        
        let max: Int64 = 1000
        
        for i in 0 ..< max {
            _ = r.add(["a": RelationValue(i), "b": RelationValue(-i)])
        }
        
        measure({
            for i in 0 ..< max {
                _ = r.delete(Attribute("a") *== RelationValue(i))
            }
        })
    }
    
    func testSaveObserver() {
        let url = tmpURL()
        let r = PlistFileRelation.withFile(url, scheme: ["n"], primaryKeys: ["n"], create: true).ok!
        
        var observedURL: URL?
        let remover = r.saveObservers.add({
            observedURL = $0
        })
        
        XCTAssertNil(r.add(["n": 42]).err)
        XCTAssertNil(r.save().err)
        
        XCTAssertEqual(url, observedURL)
        
        observedURL = nil
        remover()
        
        XCTAssertNil(r.add(["n": 43]).err)
        XCTAssertNil(r.save().err)
        
        XCTAssertNil(observedURL)
    }
    
    func testLocalFileOperations() {
        let url = tmpURL()
        let r = PlistFileRelation.withFile(url, scheme: ["n"], primaryKeys: ["n"], create: true).ok!
        
        var change: RelationChange?
        let remover = r.addChangeObserver({ change = $0 })
        
        XCTAssertNil(r.add(["n": 1]).err)
        XCTAssertNil(r.save().err)
        AssertEqual(change?.added, ConcreteRelation(["n": 1]))
        AssertEqual(change?.removed, nil)
        
        let url2 = tmpURL()
        try! FileManager.default.copyItem(at: url, to: url2)
        
        XCTAssertNil(r.add(["n": 2]).err)
        XCTAssertNil(r.save().err)
        
        AssertEqual(change?.added, ConcreteRelation(["n": 2]))
        AssertEqual(change?.removed, nil)
        
        let moveResult = r.replaceLocalFile(url: url, movingURL: url2)
        XCTAssertEqual(moveResult.ok, true)
        XCTAssertNil(moveResult.err)
        
        AssertEqual(change?.added, nil)
        AssertEqual(change?.removed, ConcreteRelation(["n": 2]))
        
        let deleteResult = r.deleteLocalFile(url: url)
        XCTAssertEqual(deleteResult.ok, true)
        XCTAssertNil(deleteResult.err)
        
        AssertEqual(change?.added, nil)
        AssertEqual(change?.removed, ConcreteRelation(["n": 1]))
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        remover()
    }
}
