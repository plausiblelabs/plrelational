//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

@testable import PLRelational
import XCTest


class ObjectMapTests: XCTestCase {
    var rand = ConsistentPRNG()
    
    func testStress() {
        let testMap = ObjectMap<String>()
        var currentEntries: Set<NSNumber> = []
        var numberObjects: [Int: NSNumber] = [:]
        func numberObject(_ x: Int) -> NSNumber {
            if let obj = numberObjects[x] {
                return obj
            } else {
                let obj = NSNumber(value: x)
                numberObjects[x] = obj
                return obj
            }
        }
        
        func add() {
            let value = numberObject(rand.next(1000))
            testMap[value] = String(value.intValue)
            currentEntries.insert(value)
        }
        
        func getOrCreate() {
            let value = numberObject(rand.next(1000))
            _ = testMap.getOrCreate(value, defaultValue: {
                currentEntries.insert(value)
                return String(value.intValue)
            }())
        }
        
        func remove() {
            let entriesArray = Array(currentEntries)
            let index = rand.next(entriesArray.count)
            let value = entriesArray[index]
            testMap[value] = nil
            currentEntries.remove(value)
        }
        
        func removeNonexistent() {
            testMap[1000000 as AnyObject] = nil
        }
        
        func verify() {
            for value in currentEntries {
                XCTAssertEqual(String(value.intValue), testMap[value])
            }
            XCTAssertEqual(testMap.count, currentEntries.count)
        }
        
        verify()
        
        for _ in 0..<2000 {
            switch rand.next(4) {
            case 0:
                add()
            case 1:
                getOrCreate()
            case 2:
                remove()
            case 3:
                removeNonexistent()
            default:
                fatalError("This should never happen")
            }
            verify()
        }
    }
}
