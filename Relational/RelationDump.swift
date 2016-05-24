
import Foundation

extension Relation {
    public func fullDebugDump(showContents showContents: Bool = true) {
        fullDebugDump(showContents, 0)
    }
    
    func fullDebugDump(showContents: Bool, _ indent: Int) {
        let indentString = "".stringByPaddingToLength(indent * 4, withString: " ", startingAtIndex: 0)
        func print(str: String) {
            for line in str.componentsSeparatedByString("\n") {
                Swift.print("\(indentString)\(line)")
            }
        }
        
        if let obj = self as? AnyObject {
            print("\(self.dynamicType) \(String(format: "%p", ObjectIdentifier(obj).uintValue))")
        } else {
            print("\(self.dynamicType)")
        }
        if showContents {
            print("\(self.description)")
        }
        
        let m = Mirror(reflecting: self)
        for (name, value) in m.children {
            if let name = name where !(value is Relation) && name != "changeObserverData" && name != "log" {
                print("\(name): \(value)")
            }
        }
        for (name, subrelation) in getChildRelationsForDump() {
            print("\(name):")
            subrelation.fullDebugDump(showContents, indent + 1)
        }
    }
    
    private func getChildRelationsForDump() -> [(String, Relation)] {
        var result: [(String, Relation)] = []
        for (name, value) in Mirror(reflecting: self).children {
            if let name = name, let subrelation = value as? Relation {
                result.append((name, subrelation))
            }
        }
        return result
    }
    
    public func simpleDump() {
        print(simpleDumpString())
    }
    
    func simpleDumpString() -> String {
        var name = String(self.dynamicType)
        if name.hasSuffix("Relation") {
            let sliceIndex = name.endIndex.advancedBy(-"Relation".characters.count)
            name = name.substringToIndex(sliceIndex)
        }
        
        let substrings = getChildRelationsForDump().map({ "\($0): \($1.simpleDumpString())" })
        let joined = substrings.joinWithSeparator(", ")
        return "\(name)(\(joined))"
    }
    
    public func uniquingDump() {
        var relationIDs: [ObjectIdentifier: Relation] = [:]
        var counts: [ObjectIdentifier: Int] = [:]
        func populateDicts(r: Relation) {
            if let obj = r as? AnyObject {
                let id = ObjectIdentifier(obj)
                counts[id] = (counts[id] ?? 0) + 1
                relationIDs[id] = r
            }
            for (_, child) in r.getChildRelationsForDump() {
                populateDicts(child)
            }
        }
        populateDicts(self)
        
        var multiples: [ObjectIdentifier] = []
        var names: [ObjectIdentifier: String] = [:]
        var cursor = 0
        func populateNames(r: Relation) {
            if let obj = r as? AnyObject {
                let id = ObjectIdentifier(obj)
                if names[id] == nil && counts[id] > 1 {
                    multiples.append(id)
                    names[id] = String(UnicodeScalar(65 + cursor))
                    cursor += 1
                }
            }
            for (_, child) in r.getChildRelationsForDump() {
                populateNames(child)
            }
        }
        populateNames(self)
        
        func dumpOrName(r: Relation) -> String {
            if let obj = r as? AnyObject, name = names[ObjectIdentifier(obj)] {
                return name
            } else {
                return rawDump(r)
            }
        }
        
        func rawDump(r: Relation) -> String {
            let name = String(r.dynamicType)
            let substrings = r.getChildRelationsForDump().map({ "\($0): \(dumpOrName($1))" })
            let joined = substrings.joinWithSeparator(", ")
            return "\(name)(\(joined))"
        }
        
        for id in multiples {
            let r = relationIDs[id]!
            let name = names[id]!
            print("\(name): \(rawDump(r))")
        }
        
        print(rawDump(self))
    }
}
