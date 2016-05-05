import XCTest
import libRelational

class ChangeLoggingRelationTests: XCTestCase {
    func testBare() {
        let underlying = MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
        )
        
        let loggingRelation = ChangeLoggingRelation(underlyingRelation: underlying)
        AssertEqual(underlying, loggingRelation)
    }
    
    func testAdd() {
        let underlying = MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
        )
        
        let loggingRelation = ChangeLoggingRelation(underlyingRelation: underlying)
        
        loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"],
                        ["42",     "Adams", "MD-11"]
            ))
        
        loggingRelation.add(["number": "43", "pilot": "Adams", "equipment": "MD-11"])
        loggingRelation.add(["number": "44", "pilot": "Adams", "equipment": "MD-11"])
        loggingRelation.add(["number": "45", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"],
                        ["42",     "Adams", "MD-11"],
                        ["43",     "Adams", "MD-11"],
                        ["44",     "Adams", "MD-11"],
                        ["45",     "Adams", "MD-11"]
            ))
    }
    
    func testDelete() {
        let underlying = MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
        )
        
        let loggingRelation = ChangeLoggingRelation(underlyingRelation: underlying)
        
        loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"],
                        ["42",     "Adams", "MD-11"]
            ))
        
        loggingRelation.delete([Attribute("number") *== "42"])
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"]
            ))
        
        loggingRelation.delete([Attribute("number") *== "123"])
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"]
            ))
    }
}
