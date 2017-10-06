//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational

class TypedRelationTests: XCTestCase {
    func testNamesAndValues() {
        enum id: TypedAttribute {
            typealias Value = Int64
        }
        enum name: TypedAttribute {
            typealias Value = String
        }
        
        let r = MakeRelation(
            [id.name, name.name],
            [1, "joe"],
            [2, "sam"]
        )
        
        AssertEqual(r, MakeRelation(
            ["id", "name"],
            [1, "joe"],
            [2, "sam"]
        ))

        let typed = r.project() as id.Relation
        
        AssertEqual(typed, MakeRelation(["id"], [1], [2]))
        
        typed.asyncAllValues({
            XCTAssertEqual($0.ok, [1, 2])
        })
        
        Async.awaitAsyncCompletion()
    }
    
    func testCustomValue() {
        enum uuid: TypedAttribute {
            typealias Value = UUID
        }
        
        let u1 = UUID(wrapped: .init())
        let u2 = UUID(wrapped: .init())
        let u3 = UUID(wrapped: .init())

        let r = MakeRelation(
            ["id", "uuid"],
            [1, .text(u1.wrapped.uuidString)],
            [2, .text(u2.wrapped.uuidString)],
            [3, .text(u3.wrapped.uuidString)])
        
        let typed = r.project() as uuid.Relation
        
        typed.asyncAllValues({
            XCTAssertEqual($0.ok, [u1, u2, u3])
        })
        
        Async.awaitAsyncCompletion()
        
        _ = r.add(["id": 4, "uuid": "xyz"])
        
        typed.asyncAllValues({
            XCTAssertNil($0.ok)
        })
        
        Async.awaitAsyncCompletion()
    }
    
    func testRowSubscript() {
        let row1: Row = ["id": 1, "name": "Timmy"]
        var row2: Row = ["id": "Stanley", "name": "Stanley"]
        
        enum id: TypedAttribute {
            typealias Value = Int64
        }
        
        XCTAssertEqual(row1[id.self], 1)
        XCTAssertEqual(row1[id.self].ok, 1)
        XCTAssertNil(row2[id.self])
        XCTAssertNil(row2[id.self].ok)
        row2[id.self] = 42
        XCTAssertEqual(row2[id.self], 42)
        row2[id.self] = nil
        XCTAssertNil(row2[id.self])
    }
}

private struct UUID: TypedAttributeValue {
    var wrapped: Foundation.UUID
    
    var toRelationValue: RelationValue {
        return .text(wrapped.uuidString)
    }
    
    static func make(from: RelationValue) -> Result<UUID, RelationError> {
        return String.make(from: from).flatMap({
            if let uuid = Foundation.UUID(uuidString: $0) {
                return .Ok(UUID(wrapped: uuid))
            } else {
                return .Err(TypedAttributeValueError.relationValueTypeMismatch)
            }
        })
    }
    
    var hashValue: Int {
        return wrapped.hashValue
    }
    
    static func ==(lhs: UUID, rhs: UUID) -> Bool {
        return lhs.wrapped == rhs.wrapped
    }
}
