//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import AppKit
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


private struct FieldNameExclusions {
    static let strings: Set = ["changeObserverData", "log", "cachedCurrentRelation"]
}

extension Relation {
    public func fullDebugDump(showContents: Bool = true) {
        fullDebugDump(showContents, 0)
    }
    
    func fullDebugDump(_ showContents: Bool, _ indent: Int) {
        let indentString = "".padding(toLength: indent * 4, withPad: " ", startingAt: 0)
        func print(_ str: String) {
            for line in str.components(separatedBy: "\n") {
                Swift.print("\(indentString)\(line)")
            }
        }
        
        if let obj = self as? AnyObject {
            print("\(type(of: self)) \(String(format: "%p", UInt(bitPattern: ObjectIdentifier(obj))))")
        } else {
            print("\(type(of: self))")
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
    
    fileprivate func getFieldsForDump() -> [(String, Any)] {
        var result: [(String, Any)] = []
        for (name, value) in Mirror(reflecting: self).childrenIncludingSupertypes {
            if let name = name , !(value is Relation) && !(value is [Relation]) && !FieldNameExclusions.strings.contains(name) {
                result.append((name, value))
            }
        }
        return result

    }
    
    fileprivate func getChildRelationsForDump() -> [(String, Relation)] {
        var result: [(String, Relation)] = []
        for (name, value) in Mirror(reflecting: self).childrenIncludingSupertypes {
            if let name = name, let subrelation = value as? Relation {
                result.append((name, subrelation))
            } else if let name = name, let subrelations = value as? [Relation] {
                for (index, subrelation) in subrelations.enumerated() {
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
        var name = String(describing: type(of: self))
        if name.hasSuffix("Relation") {
            let sliceIndex = name.characters.index(name.endIndex, offsetBy: -"Relation".characters.count)
            name = name.substring(to: sliceIndex)
        }
        
        let substrings = getChildRelationsForDump().map({ "\($0): \($1.simpleDumpString())" })
        let joined = substrings.joined(separator: ", ")
        return "\(name)(\(joined))"
    }
    
    public func uniquingDump() {
        var relationIDs: [ObjectIdentifier: Relation] = [:]
        var counts: [ObjectIdentifier: Int] = [:]
        func populateDicts(_ r: Relation) {
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
        func populateNames(_ r: Relation) {
            if let obj = r as? AnyObject {
                let id = ObjectIdentifier(obj)
                if names[id] == nil && counts[id] > 1 {
                    multiples.append(id)
                    names[id] = String(describing: UnicodeScalar(65 + cursor))
                    cursor += 1
                }
            }
            for (_, child) in r.getChildRelationsForDump() {
                populateNames(child)
            }
        }
        populateNames(self)
        
        func dumpOrName(_ r: Relation) -> String {
            if let obj = r as? AnyObject, let name = names[ObjectIdentifier(obj)] {
                return name
            } else {
                return rawDump(r)
            }
        }
        
        func rawDump(_ r: Relation) -> String {
            let name = String(describing: type(of: r))
            let substrings = r.getChildRelationsForDump().map({ "\($0): \(dumpOrName($1))" })
            let joined = substrings.joined(separator: ", ")
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
    
    public func graphvizDump(showContents: Bool = false, printer print: @escaping (String) -> Void = { print($0) }) {
        var seenIDs: Set<ObjectIdentifier> = []
        
        print("digraph relation_graph {")
        
        func visit(_ r: Relation, nonobjectID: String) -> String {
            let supplemental = r.getFieldsForDump().map({ "\($0): \($1)" })
            if let obj = r as? AnyObject {
                let id = ObjectIdentifier(obj)
                let idString = String(format: "_%lx", UInt(bitPattern: id))
                if !seenIDs.contains(id) {
                    let name = "\(type(of: r)) \(idString)"
                    var label = ([name] + supplemental).joined(separator: "\n")
                    if showContents {
                        var lines = r.description.components(separatedBy: "\n")
                        if lines.count > 10 {
                           lines = lines.prefix(10) + ["..."]
                        }
                        label += "\n" + lines.joined(separator: "\n")
                    }
                    print("\(idString) [label=\"\(label)\"]")
                    for (name, child) in r.getChildRelationsForDump() {
                        let graphID = visit(child, nonobjectID: "\(idString)xxx\(name)")
                        print("\(idString) -> \(graphID) [label=\"\(name)\"]")
                    }
                    seenIDs.insert(id)
                }
                return idString
            } else {
                let name = "\(type(of: r))"
                let label: String
                switch r {
                case let r as ConcreteRelation:
                    label = "ConcreteRelation\n\(r.description)"
                default:
                    label = ([name] + supplemental).joined(separator: "\n")
                }
                print("\(nonobjectID) [label=\"\(label)\"]")
                return nonobjectID
            }
        }
        visit(self, nonobjectID: "root")
        
        print("}")
    }
    
    public func graphvizDumpAndOpen(showContents: Bool = false) {
        var output = ""
        graphvizDump(showContents: showContents, printer: { output += $0; output += "\n" })
        
        let objDescription: String
        if let obj = self as? AnyObject {
             objDescription = "\(type(of: self)) \(String(format: "%p", UInt(bitPattern: ObjectIdentifier(obj))))"
        } else {
            objDescription = "\(type(of: self))"
        }
        
        var filename = "/tmp/\(objDescription).dot"
        var counter = 2
        if FileManager.default.fileExists(atPath: filename) {
            filename = "/tmp/\(objDescription) \(counter).dot"
            counter += 1
        }
        try! output.write(toFile: filename, atomically: true, encoding: String.Encoding.utf8)
        NSWorkspace.shared().openFile(filename, withApplication: "Graphviz")
    }
}
