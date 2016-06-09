
import AppKit

private struct FieldNameExclusions {
    static let strings: Set = ["changeObserverData", "log", "cachedCurrentRelation"]
}

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
            print("\(self.descriptionWithRows(self.rows()))")
        }
        
        for (name, value) in getFieldsForDump() {
            print("\(name): \(value)")
        }
        for (name, subrelation) in getChildRelationsForDump() {
            print("\(name):")
            subrelation.fullDebugDump(showContents, indent + 1)
        }
    }
    
    private func getFieldsForDump() -> [(String, Any)] {
        var result: [(String, Any)] = []
        for (name, value) in Mirror(reflecting: self).childrenIncludingSupertypes {
            if let name = name where !(value is Relation) && !(value is [Relation]) && !FieldNameExclusions.strings.contains(name) {
                result.append((name, value))
            }
        }
        return result

    }
    
    private func getChildRelationsForDump() -> [(String, Relation)] {
        var result: [(String, Relation)] = []
        for (name, value) in Mirror(reflecting: self).childrenIncludingSupertypes {
            if let name = name, let subrelation = value as? Relation {
                result.append((name, subrelation))
            } else if let name = name, let subrelations = value as? [Relation] {
                for (index, subrelation) in subrelations.enumerate() {
                    result.append(("\(name)_\(index)", subrelation))
                }
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
            let count = counts[id]!
            print("\(name): \(rawDump(r)) (referenced \(count) times)")
        }
        
        print(rawDump(self))
    }
    
    public func graphvizDump(showContents showContents: Bool = false, printer print: String -> Void = { print($0) }) {
        var seenIDs: Set<ObjectIdentifier> = []
        
        print("digraph relation_graph {")
        
        func visit(r: Relation, nonobjectID: String) -> String {
            let supplemental = r.getFieldsForDump().map({ "\($0): \($1)" })
            if let obj = r as? AnyObject {
                let id = ObjectIdentifier(obj)
                let idString = String(format: "_%lx", id.uintValue)
                if !seenIDs.contains(id) {
                    let name = "\(r.dynamicType) \(idString)"
                    let label = ([name] + supplemental).joinWithSeparator("\n") + (showContents ? "\n" + r.description : "")
                    print("\(idString) [label=\"\(label)\"]")
                    for (name, child) in r.getChildRelationsForDump() {
                        let graphID = visit(child, nonobjectID: "\(idString)xxx\(name)")
                        print("\(idString) -> \(graphID) [label=\"\(name)\"]")
                    }
                    seenIDs.insert(id)
                }
                return idString
            } else {
                let name = "\(r.dynamicType)"
                let label: String
                switch r {
                case let r as ConcreteRelation:
                    label = "ConcreteRelation\n\(r.description)"
                default:
                    label = ([name] + supplemental).joinWithSeparator("\n")
                }
                print("\(nonobjectID) [label=\"\(label)\"]")
                return nonobjectID
            }
        }
        visit(self, nonobjectID: "root")
        
        print("}")
    }
    
    public func graphvizDumpAndOpen(showContents showContents: Bool = false) {
        var output = ""
        graphvizDump(showContents: showContents, printer: { output += $0; output += "\n" })
        
        let objDescription: String
        if let obj = self as? AnyObject {
             objDescription = "\(self.dynamicType) \(String(format: "%p", ObjectIdentifier(obj).uintValue))"
        } else {
            objDescription = "\(self.dynamicType)"
        }
        
        let filename = "/tmp/\(objDescription).dot"
        try! output.writeToFile(filename, atomically: true, encoding: NSUTF8StringEncoding)
        NSWorkspace.sharedWorkspace().openFile(filename, withApplication: "Graphviz")
    }
}
