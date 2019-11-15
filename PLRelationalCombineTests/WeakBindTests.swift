//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import Combine
import PLRelational
@testable import PLRelationalCombine

class WeakBindTests: CombineTestCase {

    func testLifetime() {

        class TestObject {
            var value: String = ""
            private var cancellableBag = Set<AnyCancellable>()

            init(names: Relation) {
                // This is a long-lived publisher that will continue to observe
                // the underlying relation until it is cancelled (and it will be
                // cancelled once there are no more references to this
                // TestObject instance)
                names
                    .oneString()
                    .replaceError(with: "")
                    .bind(to: \.value, on: self)
                    .store(in: &cancellableBag)
            }
            
            deinit {
                cancellableBag.forEach{ $0.cancel() }
            }
        }
        
        let names = MakeRelation(["name"], ["fred"])
        var obj: TestObject? = TestObject(names: names)
        weak var weakObj = obj
        
        awaitIdle()
        XCTAssertEqual(weakObj?.value, "fred")
        
        // Verify that `bind` holds the given object weakly
        obj = nil
        XCTAssertNil(weakObj)
    }
}
