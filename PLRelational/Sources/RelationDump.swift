//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

#if os(OSX)
    import AppKit
    private func open(_ filename: String) {
        NSWorkspace.shared.openFile(filename, withApplication: "Graphviz")
    }
#elseif os(iOS)
    import UIKit
    private func open(_ filename: String) {
        print("WROTE \(filename)")
    }
#endif

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
    static let strings: Set = ["changeObserverData", "log", "cachedCurrentRelation", "values"]
}

/// :nodoc: Debugging aids are hidden from "official" API for now; may be exposed in the future
extension Relation {
    public func fullDebugDump(options: Set<GraphvizDumpOption> = [.showContents]) {
        fullDebugDump(options, 0)
    }
    
    func fullDebugDump(_ options: Set<GraphvizDumpOption>, _ indent: Int) {
        let indentString = "".padding(toLength: indent * 4, withPad: " ", startingAt: 0)
        func print(_ str: String) {
            for line in str.components(separatedBy: "\n") {
                Swift.print("\(indentString)\(line)")
            }
        }
        
        if let obj = asObject(self) {
            print("\(type(of: self)) \(String(format: "%p", UInt(bitPattern: ObjectIdentifier(obj))))")
        } else {
            print("\(type(of: self))")
        }
        if options.contains(.showContents) {
            print("\(self.descriptionWithRows(self.rows()))")
        }
        
        for (name, value) in getFieldsForDump() {
            print("\(name): \(value)")
        }
        for (name, subrelation) in getChildRelationsForDump() {
            print("\(name):")
            subrelation.fullDebugDump(options, indent + 1)
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
            let sliceIndex = name.index(name.endIndex, offsetBy: -"Relation".count)
            name = String(name[..<sliceIndex])
        }
        
        let substrings = getChildRelationsForDump().map({ "\($0): \($1.simpleDumpString())" })
        let joined = substrings.joined(separator: ", ")
        return "\(name)(\(joined))"
    }
    
    public func uniquingDump() {
        var relationIDs: [ObjectIdentifier: Relation] = [:]
        var counts: [ObjectIdentifier: Int] = [:]
        func populateDicts(_ r: Relation) {
            if let obj = asObject(r) {
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
            if let obj = asObject(r) {
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
            if let obj = asObject(r), let name = names[ObjectIdentifier(obj)] {
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
    
    public func graphvizDump(options: Set<GraphvizDumpOption> = [], printer print: @escaping (String) -> Void = { print($0) }) {
        var seenIDs: Set<ObjectIdentifier> = []
        
        print("digraph relation_graph {")
        
        func visit(_ r: Relation, nonobjectID: String) -> String {
            let supplemental: [String] = r.getFieldsForDump().compactMap({
                if  ($0 == "debugName" && !options.contains(.showDebugName)) ||
                    ($0 == "derivative" && !options.contains(.showDerivative)) ||
                    ($0 == "inTransaction" && !options.contains(.showInTransaction)) ||
                    ($0 == "didRegisterObservers" && !options.contains(.showDidRegisterObservers))
                {
                    return nil
                }
                let valueString: String
                switch $1 {
                case let opt as String:
                    valueString = opt
                case nil:
                    valueString = "nil"
                default:
                    valueString = String(describing: $1)
                }
                let valueStringEscaped = valueString.replacingOccurrences(of: "\"", with: "\\\"")
                return "\($0): \(valueStringEscaped)"
            })
            if let obj = asObject(r) {
                let id = ObjectIdentifier(obj)
                let idString = String(format: "_%lx", UInt(bitPattern: id))
                if !seenIDs.contains(id) {
                    let type = String(describing: Swift.type(of: r))
                    let name = options.contains(.showAddress) ? type + " " + idString : type
                    var label = ([name] + supplemental).joined(separator: "\n")
                    if options.contains(.showContents) {
                        var lines = r.description.components(separatedBy: "\n")
                        if lines.count > 6 {
                           lines = lines.prefix(6) + ["..."]
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
        _ = visit(self, nonobjectID: "root")
        
        print("}")
    }
    
    public func graphvizDumpAndOpen(options: Set<GraphvizDumpOption> = []) {
        var output = ""
        graphvizDump(options: options, printer: { output += $0; output += "\n" })
        
        let objDescription: String
        if let obj = asObject(self) {
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
        open(filename)
    }
    
    public func dumpAsCode(print: @escaping (String) -> Void = { print($0, terminator: "") }) {
        var lastNumber = 0
        var relationNumbers: ObjectDictionary<AnyObject, Int> = [:]
        
        func codeForValue(_ value: RelationValue) -> String {
            switch value {
            case .null: return ".null"
            case .integer(let x): return String(x)
            case .real(let x): return String(x)
            case .text(let x): return "\"\(x)\""
            case .blob: return ".blob([…SOME BLOB HERE…])"
            case .notFound: return ".notFound"
            }
        }
        
        func visit(_ r: Relation) -> Int {
            if let obj = asObject(r) {
                if let n = relationNumbers[obj] {
                    return n
                } else {
                    relationNumbers[obj] = lastNumber
                }
            }
            
            if case let r as IntermediateRelation = r {
                let numbers = r.operands.map(visit)
                print("let r\(lastNumber) = ")
                switch r.op {
                case .union:
                    if numbers.count == 2 {
                        print("r\(numbers[0]).union(r\(numbers[1]))\n")
                    } else {
                        print("IntermediateRelation.union([")
                        print(numbers.map({ "r\($0)" }).joined(separator: ", "))
                        print("])\n")
                    }
                    
                case .intersection:
                    if numbers.count == 2 {
                        print("r\(numbers[0]).intersection(r\(numbers[1]))\n")
                    } else {
                        print("intersection([")
                        print(numbers.map({ "r\($0)" }).joined(separator: ", "))
                        print("])\n")
                    }
                    
                case .difference:
                    if numbers.count == 2 {
                        print("r\(numbers[0]).difference(r\(numbers[1]))\n")
                    } else {
                        print("IntermediateRelation(op: .difference, operands: [")
                        print(numbers.map({ "r\($0)" }).joined(separator: ", "))
                        print("])\n")
                    }
                    
                case .project(let scheme):
                    print("r\(numbers[0]).project([")
                    print(scheme.attributes.map({ "\"\($0.name)\"" }).joined(separator: ", "))
                    print("])\n")
                    
                case .select(let query):
                    print("r\(numbers[0]).select(\(query))\n")
                    
                case .mutableSelect(let query):
                    print("r\(numbers[0]).mutableSelect(\(query))\n")
                    
                case .equijoin(let mapping):
                    print("r\(numbers[0]).equijoin(r\(numbers[1]), matching: [")
                    print(mapping.map({ "\"\($0)\": \"\($1)\"" }).joined(separator: ", "))
                    print("])\n")
                    
                case .rename(let mapping):
                    print("r\(numbers[0]).rename(")
                    print(mapping.map({ "\"\($0)\": \"\($1)\"" }).joined(separator: ", "))
                    print("])\n")
                    
                case .update(let row):
                    print("r\(numbers[0]).withUpdate([")
                    print(row.map({ "\"\($0.name)\": \(codeForValue($1))" }).joined(separator: ", "))
                    print("])\n")
                    
                case .aggregate(let attribute, let initialValue, _):
                    print("r\(numbers[0]).someAggregateFunction(\(attribute), \(initialValue?.description ?? "nil"))\n")
                    
                case .otherwise:
                    print("r\(numbers[0]).otherwise(r\(numbers[1]))\n")
                    
                case .unique(let attribute, let value):
                    print("r\(numbers[0]).unique(\"\(attribute.name)\", matching: \(codeForValue(value)))\n")
                }
            } else {
                print("let r\(lastNumber) = MakeRelation(\n")
                print("[\"")
                let sortedScheme = r.scheme.attributes.map({ $0.name }).sorted()
                print(sortedScheme.joined(separator: "\", \""))
                print("\"]\n")
                
                for rowResult in r.rows() {
                    let row = rowResult.ok!
                    let contents = sortedScheme.map({ row[Attribute($0)] })
                    print(",[")
                    print(contents.map(codeForValue).joined(separator: ", "))
                    print("]\n")
                }
                
                print(")\n")
            }
            
            lastNumber += 1
            return lastNumber - 1
        }
        _ = visit(self)
    }
}

public enum GraphvizDumpOption {
    case showAddress
    case showContents
    
    case showDebugName
    case showDerivative
    case showInTransaction
    case showDidRegisterObservers
}
