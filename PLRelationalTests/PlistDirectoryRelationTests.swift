//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational


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
        let result = PlistDirectoryRelation.withDirectory(tmpURL(), scheme: ["a"], primaryKey: "a", create: false)
        XCTAssertNotNil(result.err)
    }
    
    func testEmptyRoundTrip() {
        let url = tmpURL()
        
        let r1Result = PlistDirectoryRelation.withDirectory(url, scheme: ["a"], primaryKey: "a", create: true)
        XCTAssertNil(r1Result.err)
        let r1 = r1Result.ok!
        
        let r2Result = PlistDirectoryRelation.withDirectory(url, scheme: ["a"], primaryKey: "a", create: true)
        XCTAssertNil(r2Result.err)
        let r2 = r2Result.ok!
        
        AssertEqual(r1, r2)
    }
    
    func testEmptyRoundTripWithUnsetURL() {
        let r1Result = PlistDirectoryRelation.withDirectory(nil, scheme: ["a"], primaryKey: "a", create: true)
        XCTAssertNil(r1Result.err)
        let r1 = r1Result.ok!
        
        let r2Result = PlistDirectoryRelation.withDirectory(nil, scheme: ["a"], primaryKey: "a", create: true)
        XCTAssertNil(r2Result.err)
        let r2 = r2Result.ok!
        
        AssertEqual(r1, r2)
    }
    
    func testAddUpdateDelete() {
        let r = PlistDirectoryRelation.withDirectory(tmpURL(), scheme: ["n"], primaryKey: "n", create: true).ok!
        
        AssertEqual(r, MakeRelation(["n"]))
        
        XCTAssertNil(r.add(["n": 1]).err)
        AssertEqual(r, MakeRelation(["n"], [1]))
        
        XCTAssertNil(r.update(true, newValues: ["n": 2]).err)
        AssertEqual(r, MakeRelation(["n"], [2]))
        
        XCTAssertNil(r.delete(true).err)
        AssertEqual(r, MakeRelation(["n"]))
    }
    
    func testAddUpdateDeleteSave() {
        let r = PlistDirectoryRelation.withDirectory(tmpURL(), scheme: ["n"], primaryKey: "n", create: true).ok!
        
        XCTAssertNil(r.add(["n": 1]).err)
        XCTAssertNil(r.update(true, newValues: ["n": 2]).err)
        XCTAssertNil(r.delete(true).err)
        XCTAssertNil(r.save().err)
        AssertEqual(r, MakeRelation(["n"]))
    }
    
    func testAddUpdateDeleteWithoutURL() {
        let r = PlistDirectoryRelation.withDirectory(nil, scheme: ["n"], primaryKey: "n", create: true).ok!
        
        AssertEqual(r, MakeRelation(["n"]))
        
        XCTAssertNil(r.add(["n": 1]).err)
        AssertEqual(r, MakeRelation(["n"], [1]))
        
        XCTAssertNil(r.update(true, newValues: ["n": 2]).err)
        AssertEqual(r, MakeRelation(["n"], [2]))
        
        XCTAssertNil(r.delete(true).err)
        AssertEqual(r, MakeRelation(["n"]))
    }
    
    func testAddUpdateDeleteWithSave() {
        let r = PlistDirectoryRelation.withDirectory(tmpURL(), scheme: ["n"], primaryKey: "n", create: true).ok!
        
        AssertEqual(r, MakeRelation(["n"]))
        XCTAssertNil(r.save().err)
        AssertEqual(r, MakeRelation(["n"]))
        
        XCTAssertNil(r.add(["n": 1]).err)
        AssertEqual(r, MakeRelation(["n"], [1]))
        XCTAssertNil(r.save().err)
        AssertEqual(r, MakeRelation(["n"], [1]))
        
        XCTAssertNil(r.update(true, newValues: ["n": 2]).err)
        AssertEqual(r, MakeRelation(["n"], [2]))
        XCTAssertNil(r.save().err)
        AssertEqual(r, MakeRelation(["n"], [2]))
        
        XCTAssertNil(r.delete(true).err)
        AssertEqual(r, MakeRelation(["n"]))
        XCTAssertNil(r.save().err)
        AssertEqual(r, MakeRelation(["n"]))
    }
    
    func testDataRoundTrip() {
        let url = tmpURL()
        
        let schemeAttributes: [Attribute] = ["first", "last", "job"]
        let r1Result = PlistDirectoryRelation.withDirectory(url, scheme: Scheme(attributes: Set(schemeAttributes)), primaryKey: "first", create: true)
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
        
        XCTAssertNil(r1.save().err)
        
        let r2Result = PlistDirectoryRelation.withDirectory(url, scheme: r1.scheme, primaryKey: "first", create: true)
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
        let r1Result = PlistDirectoryRelation.withDirectory(url, scheme: Scheme(attributes: Set(schemeAttributes)), primaryKey: "first", create: true, codec: PrefixCodec())
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
        
        XCTAssertNil(r1.save().err)
        
        let r2Result = PlistDirectoryRelation.withDirectory(url, scheme: r1.scheme, primaryKey: "first", create: true, codec: PrefixCodec())
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
        let r1Result = PlistDirectoryRelation.withDirectory(url, scheme: Scheme(attributes: Set(schemeAttributes)), primaryKey: "first", create: true)
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
        let r1Result = PlistDirectoryRelation.withDirectory(nil, scheme: Scheme(attributes: Set(schemeAttributes)), primaryKey: "first", create: true)
        XCTAssertNil(r1Result.err)
        let r1 = r1Result.ok!
        
        XCTAssertEqual(r1.contains(["first": "Steve", "last": "Jobs", "job": "CEO"]).ok, false)
    }
    
    func testUpdateDelete() {
        let url = tmpURL()
        
        let schemeAttributes: [Attribute] = ["first", "last", "job"]
        let r1Result = PlistDirectoryRelation.withDirectory(url, scheme: Scheme(attributes: Set(schemeAttributes)), primaryKey: "first", create: true)
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
    
    func testJoinPerformance() {
        let url = tmpURL()
        
        let loggingCodec = LoggingCodec()
        
        let initialValues = MakeRelation(
            ["id", "name"],
            [1, "Bob"],
            [2, "Susan"],
            [3, "Jane"],
            [4, "Pat"],
            [5, "Steve"]
        )
        let dirRResult = PlistDirectoryRelation.withDirectory(url, scheme: initialValues.scheme, primaryKey: "id", create: true, codec: loggingCodec)
        XCTAssertNil(dirRResult.err)
        let dirR = dirRResult.ok!
        
        for row in initialValues.rows() {
            _ = dirR.add(row.ok!)
        }
        XCTAssertNil(dirR.save().err)
        
        let toSubtract = MakeRelation(["id", "name"], [4, "Pat"])
        let toUnion = MakeRelation(["id", "name"], [6, "Sam"])
        let toJoin = MakeRelation(["id"])
        
        let output = dirR.difference(toSubtract).union(toUnion).join(toJoin)
        
        loggingCodec.encoded = []
        loggingCodec.decoded = []
        AssertEqual(output, MakeRelation(["id", "name"]))
        XCTAssertEqual(loggingCodec.decoded.count, 0)
        
        _ = toJoin.add(["id": 2])
        loggingCodec.encoded = []
        loggingCodec.decoded = []
        AssertEqual(output, MakeRelation(["id", "name"], [2, "Susan"]))
        XCTAssertEqual(loggingCodec.decoded.count, 1)
        
        _ = toJoin.delete(true)
        _ = toJoin.add(["id": 12345])
        loggingCodec.encoded = []
        loggingCodec.decoded = []
        AssertEqual(output, MakeRelation(["id", "name"]))
        XCTAssertEqual(loggingCodec.decoded.count, 0)
    }
    
    func testSelectPerformance() {
        let url = tmpURL()
        
        let loggingCodec = LoggingCodec()
        
        let initialValues = MakeRelation(
            ["id", "name"],
            [1, "Bob"],
            [2, "Susan"],
            [3, "Jane"],
            [4, "Pat"],
            [5, "Steve"]
        )
        let dirRResult = PlistDirectoryRelation.withDirectory(url, scheme: initialValues.scheme, primaryKey: "id", create: true, codec: loggingCodec)
        XCTAssertNil(dirRResult.err)
        let dirR = dirRResult.ok!
        
        for row in initialValues.rows() {
            _ = dirR.add(row.ok!)
        }
        XCTAssertNil(dirR.save().err)
        
        let toSubtract = MakeRelation(["id", "name"], [4, "Pat"])
        let toUnion = MakeRelation(["id", "name"], [6, "Sam"])
        
        let combined = dirR.difference(toSubtract).union(toUnion)
        
        loggingCodec.encoded = []
        loggingCodec.decoded = []
        AssertEqual(combined.select(false), MakeRelation(["id", "name"]))
        XCTAssertEqual(loggingCodec.decoded.count, 0)
        
        loggingCodec.encoded = []
        loggingCodec.decoded = []
        AssertEqual(combined.select(Attribute("id") *== 2), MakeRelation(["id", "name"], [2, "Susan"]))
        XCTAssertEqual(loggingCodec.decoded.count, 1)
        
        loggingCodec.encoded = []
        loggingCodec.decoded = []
        AssertEqual(combined.select(Attribute("id") *== 12345), MakeRelation(["id", "name"]))
        XCTAssertEqual(loggingCodec.decoded.count, 0)
    }
    
    func testReadCache() {
        let loggingCodec = LoggingCodec()
        let r = PlistDirectoryRelation.withDirectory(tmpURL(), scheme: ["n"], primaryKey: "n", create: true, codec: loggingCodec).ok!
        
        XCTAssertNil(r.add(["n": 1]).err)
        XCTAssertNil(r.save().err)
        
        loggingCodec.encoded = []
        loggingCodec.decoded = []
        for _ in 0 ..< 100 {
            AssertEqual(r, MakeRelation(["n"], [1]))
        }
        XCTAssertEqual(loggingCodec.encoded.count, 0)
        XCTAssertTrue(loggingCodec.decoded.count > 0)
        XCTAssertTrue(loggingCodec.decoded.count < 100)
    }
    
    func testSchemeMismatch() {
        let url = tmpURL()
        let r1Result = PlistDirectoryRelation.withDirectory(url, scheme: ["n"], primaryKey: "n", create: true)
        XCTAssertNil(r1Result.err)
        
        XCTAssertNil(r1Result.ok?.add(["n": 1]).err)
        XCTAssertNil(r1Result.ok?.save().err)
        
        let r2Result = PlistDirectoryRelation.withDirectory(url, scheme: ["m"], primaryKey: "m", create: true)
        XCTAssertNil(r2Result.err)
        XCTAssertNotNil(r2Result.ok?.rows().first(where: { _ in true })?.err)
    }
    
    func testSaveObserver() {
        let url = tmpURL()
        let r = PlistDirectoryRelation.withDirectory(url, scheme: ["n"], primaryKey: "n", create: true).ok!
        
        var observedURLs: [URL] = []
        let remover = r.saveObservers.add({
            observedURLs.append($0)
        })
        
        XCTAssertNil(r.add(["n": 42]).err)
        XCTAssertNil(r.add(["n": 43]).err)
        XCTAssertNil(r.save().err)
        
        XCTAssertEqual(observedURLs.count, 2)
        for observedURL in observedURLs {
            XCTAssertTrue(observedURL.path.hasPrefix(url.path))
        }
        
        observedURLs = []
        XCTAssertNil(r.delete(Attribute("n") *== 42).err)
        XCTAssertNil(r.save().err)
        XCTAssertEqual(observedURLs.count, 1)
        for observedURL in observedURLs {
            XCTAssertTrue(observedURL.path.hasPrefix(url.path))
        }
        
        observedURLs = []
        remover()
        
        XCTAssertNil(r.add(["n": 44]).err)
        XCTAssertNil(r.add(["n": 45]).err)
        XCTAssertNil(r.save().err)
        
        XCTAssertEqual(observedURLs, [])
    }
    
    func testLocalFileOperations() {
        let url = tmpURL()
        let r = PlistDirectoryRelation.withDirectory(url, scheme: ["n", "text"], primaryKey: "n", create: true).ok!
        
        var change: RelationChange?
        let remover = r.addChangeObserver({ change = $0 })
        
        XCTAssertNil(r.add(["n": 1, "text": "one"]).err)
        XCTAssertNil(r.save().err)
        
        AssertEqual(change?.added, ConcreteRelation(["n": 1, "text": "one"]))
        AssertEqual(change?.removed, nil)
        
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)!
        let files = enumerator.map({ $0 as! URL }).filter({ $0.isDirectory.ok == false })
        XCTAssertEqual(files.count, 1)
        let rowURL = files[0]
        
        XCTAssertNil(r.add(["n": 2, "text": "two"]).err)
        XCTAssertNil(r.save().err)
        
        AssertEqual(change?.added, ConcreteRelation(["n": 2, "text": "two"]))
        AssertEqual(change?.removed, nil)
        
        let rowURL2 = tmpURL()
        try! FileManager.default.copyItem(at: rowURL, to: rowURL2)
        
        XCTAssertNil(r.update(Attribute("n") *== 1, newValues: ["text": "WON"]).err)
        XCTAssertNil(r.save().err)
        
        AssertEqual(change?.added, ConcreteRelation(["n": 1, "text": "WON"]))
        AssertEqual(change?.removed, ConcreteRelation(["n": 1, "text": "one"]))
        
        let replaceResult = r.replaceLocalFile(url: rowURL, movingURL: rowURL2)
        XCTAssertEqual(replaceResult.ok, true)
        XCTAssertNil(replaceResult.err)
        
        AssertEqual(change?.added, ConcreteRelation(["n": 1, "text": "one"]))
        AssertEqual(change?.removed, ConcreteRelation(["n": 1, "text": "WON"]))
        
        let deleteResult = r.deleteLocalFile(url: rowURL)
        XCTAssertEqual(deleteResult.ok, true)
        XCTAssertNil(deleteResult.err)
        
        AssertEqual(change?.added, nil)
        AssertEqual(change?.removed, ConcreteRelation(["n": 1, "text": "one"]))
        
        remover()
    }
}

fileprivate class LoggingCodec: DataCodec {
    var encoded: [Data] = []
    var decoded: [Data] = []
    
    func encode(_ data: Data) -> Result<Data, RelationError> {
        encoded.append(data)
        return .Ok(data)
    }
    
    func decode(_ data: Data) -> Result<Data, RelationError> {
        decoded.append(data)
        return .Ok(data)
    }
}
