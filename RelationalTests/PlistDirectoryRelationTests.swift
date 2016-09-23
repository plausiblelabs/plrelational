//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational


class PlistDirectoryRelationTests: XCTestCase {
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
        let result = PlistDirectoryRelation.withDirectory(tmpURL(), scheme: ["a"], primaryKey: "a", createIfDoesntExist: false)
        XCTAssertNotNil(result.err)
    }
    
    func testEmptyRoundTrip() {
        let url = tmpURL()
        
        let r1Result = PlistDirectoryRelation.withDirectory(url, scheme: ["a"], primaryKey: "a", createIfDoesntExist: true)
        XCTAssertNil(r1Result.err)
        let r1 = r1Result.ok!
        
        let r2Result = PlistDirectoryRelation.withDirectory(url, scheme: ["a"], primaryKey: "a", createIfDoesntExist: true)
        XCTAssertNil(r2Result.err)
        let r2 = r2Result.ok!
        
        AssertEqual(r1, r2)
    }
    
    func testEmptyRoundTripWithUnsetURL() {
        let r1Result = PlistDirectoryRelation.withDirectory(nil, scheme: ["a"], primaryKey: "a", createIfDoesntExist: true)
        XCTAssertNil(r1Result.err)
        let r1 = r1Result.ok!
        
        let r2Result = PlistDirectoryRelation.withDirectory(nil, scheme: ["a"], primaryKey: "a", createIfDoesntExist: true)
        XCTAssertNil(r2Result.err)
        let r2 = r2Result.ok!
        
        AssertEqual(r1, r2)
    }
    
    func testDataRoundTrip() {
        let url = tmpURL()
        
        let schemeAttributes: [Attribute] = ["first", "last", "job"]
        let r1Result = PlistDirectoryRelation.withDirectory(url, scheme: Scheme(attributes: Set(schemeAttributes)), primaryKey: "first", createIfDoesntExist: true)
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
            XCTAssertNil(r1.add(row).err)
        }
        
        let r2Result = PlistDirectoryRelation.withDirectory(url, scheme: r1.scheme, primaryKey: "first", createIfDoesntExist: true)
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
        let r1Result = PlistDirectoryRelation.withDirectory(url, scheme: Scheme(attributes: Set(schemeAttributes)), primaryKey: "first", createIfDoesntExist: true, codec: PrefixCodec())
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
            XCTAssertNil(r1.add(row).err)
        }
        
        let r2Result = PlistDirectoryRelation.withDirectory(url, scheme: r1.scheme, primaryKey: "first", createIfDoesntExist: true, codec: PrefixCodec())
        XCTAssertNil(r2Result.err)
        let r2 = r2Result.ok!
        
        AssertEqual(r1, r2)
        
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: nil)!
        for innerURLAny in enumerator {
            let innerURL = innerURLAny as! URL
            if innerURL.isDirectory.ok == false {
                let contents = try! Data(contentsOf: innerURL)
                XCTAssertTrue(contents.starts(with: PrefixCodec.prefix.utf8))
            }
        }
    }
    
    func testContains() {
        let url = tmpURL()
        
        let schemeAttributes: [Attribute] = ["first", "last", "job"]
        let r1Result = PlistDirectoryRelation.withDirectory(url, scheme: Scheme(attributes: Set(schemeAttributes)), primaryKey: "first", createIfDoesntExist: true)
        XCTAssertNil(r1Result.err)
        let r1 = r1Result.ok!
        
        let testRowValues: [[RelationValue]] = [
            ["Steve", "Jobs", "CEO"],
            ["Bob", "Dole", "Senator"],
            ["Tim", "Allen", "Pharmacist"],
            ["Steven", "Tyler", "Musician"],
            [.null, 42, 666.0],
            [0, 0, RelationValue.blob([1, 2, 3, 4, 5])],
            [0.0, 0, 0],
            [RelationValue.blob([1, 2, 3, 4, 5]), 0, 0]
        ]
        
        for rowValues in testRowValues {
            let row = Row(values: Dictionary(zip(schemeAttributes, rowValues)))
            XCTAssertNil(r1.add(row).err)
        }
        
        XCTAssertEqual(r1.contains(["first": "Steve", "last": "Jobs", "job": "CEO"]).ok, true)
        XCTAssertEqual(r1.contains(["first": "Bob", "last": "Dole", "job": "Senator"]).ok, true)
        XCTAssertEqual(r1.contains(["first": "Steve", "last": "Jobs", "job": "Senator"]).ok, false)
        XCTAssertEqual(r1.contains(["first": "Billybob", "last": "Jobs", "job": "CEO"]).ok, false)
        
        XCTAssertEqual(r1.contains(["first": .null, "last": 42, "job": 666.0]).ok, true)
        XCTAssertEqual(r1.contains(["first": .null, "last": "Jobs", "job": "CEO"]).ok, false)
        
        XCTAssertEqual(r1.contains(["first": 0, "last": 0, "job": .blob([1, 2, 3, 4, 5])]).ok, true)
        XCTAssertEqual(r1.contains(["first": 0, "last": 0, "job": .blob([1, 2, 3, 4, 6])]).ok, false)
        XCTAssertEqual(r1.contains(["first": 1, "last": 0, "job": .blob([1, 2, 3, 4, 5])]).ok, false)
        
        XCTAssertEqual(r1.contains(["first": 0.0, "last": 0, "job": 0]).ok, true)
        XCTAssertEqual(r1.contains(["first": 0.0, "last": 0, "job": 1]).ok, false)
        XCTAssertEqual(r1.contains(["first": 0.1, "last": 0, "job": 0]).ok, false)
        
        XCTAssertEqual(r1.contains(["first": .blob([1, 2, 3, 4, 5]), "last": 0, "job": 0]).ok, true)
        XCTAssertEqual(r1.contains(["first": .blob([1, 2, 3, 4, 5]), "last": 0, "job": 1]).ok, false)
        XCTAssertEqual(r1.contains(["first": .blob([1, 2, 3, 4, 6]), "last": 0, "job": 0]).ok, false)
    }
    
    func testContainsWithEmptyRelationAndUnsetURL() {
        let schemeAttributes: [Attribute] = ["first", "last", "job"]
        let r1Result = PlistDirectoryRelation.withDirectory(nil, scheme: Scheme(attributes: Set(schemeAttributes)), primaryKey: "first", createIfDoesntExist: true)
        XCTAssertNil(r1Result.err)
        let r1 = r1Result.ok!
        
        XCTAssertEqual(r1.contains(["first": "Steve", "last": "Jobs", "job": "CEO"]).ok, false)
    }
    
    func testUpdateDelete() {
        let url = tmpURL()
        
        let schemeAttributes: [Attribute] = ["first", "last", "job"]
        let r1Result = PlistDirectoryRelation.withDirectory(url, scheme: Scheme(attributes: Set(schemeAttributes)), primaryKey: "first", createIfDoesntExist: true)
        XCTAssertNil(r1Result.err)
        let r1 = r1Result.ok!
        
        let testRowValues: [[RelationValue]] = [
            ["Steve", "Jobs", "CEO"],
            ["Bob", "Dole", "Senator"],
            ["Tim", "Allen", "Pharmacist"],
            ["Steven", "Tyler", "Musician"],
            [.null, 42, 666.0],
            [0, 0, RelationValue.blob([1, 2, 3, 4, 5])],
            [0.0, 0, 0],
            [RelationValue.blob([1, 2, 3, 4, 5]), 0, 0]
        ]
        
        for rowValues in testRowValues {
            let row = Row(values: Dictionary(zip(schemeAttributes, rowValues)))
            XCTAssertNil(r1.add(row).err)
        }
        
        _ = r1.update(Attribute("job") *== "CEO", newValues: ["last": "Mobs"])
        _ = r1.update(Attribute("job") *== "Musician" *|| Attribute("first") *== 0, newValues: ["last": "Empty"])
        _ = r1.delete(Attribute("first") *== "Bob")
        _ = r1.delete(Attribute("job") *== 0 *&& Attribute("last") *== 1)
        _ = r1.delete(Attribute("job") *== 0 *&& Attribute("first") *== RelationValue(0.0))
        
        AssertEqual(r1,
                    MakeRelation(
                        ["first", "last", "job"],
                        ["Steve", "Mobs", "CEO"],
                        ["Tim", "Allen", "Pharmacist"],
                        ["Steven", "Empty", "Musician"],
                        [.null, 42, 666.0],
                        [0, "Empty", RelationValue.blob([1, 2, 3, 4, 5])],
                        [RelationValue.blob([1, 2, 3, 4, 5]), 0, 0]
            ))
    }
}
