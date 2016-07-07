//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import Binding

class PiTests: BindingTestCase {
    
    func testIncr() {
        // This is an expression of the client/server RPC example from:
        //   https://www.cs.cmu.edu/~wing/publications/Wing02a.pdf
        
        let server =
            rcv(on: "incr", bind: bpair("c", "x"), then:
                snd(on: "c", value: incr("x"))
            )
        let client =
            newc("a", then:
                snd(on: "incr", value: vpair("a", 17))
                *|*
                rcv(on: "a", bind: intb("y"))
            )
        let pi = server *|* client

        XCTAssertEqual(pi.description, "incr(c,x).c<x+1> | (nu a)(incr<a,17> | a(y))")
        
        var env = PiEnv()
        runPi(pi, env: &env)
    }
}
