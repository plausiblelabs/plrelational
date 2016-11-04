//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import AppKit


extension QueryPlanner {
    func graphvizDump(printer print: (String) -> Void = { print($0) }) {
        print("digraph query_planner_graph {")
        
        func nodename(_ index: Int) -> String {
            return "node_\(index)"
        }
        
        for (index, node) in nodes.enumerated() {
            var opLines = String(describing: node.op).components(separatedBy: "\n")
            if opLines.count > 10 {
                opLines = opLines.prefix(10) + ["..."]
            }
            let opString = opLines.joined(separator: "\n")
            let label = "\(nodename(index)) \(opString)"
            print("\(nodename(index)) [label=\"\(label)\"]")
            for parentIndex in node.parentIndexes {
                let childIndex = nodes[parentIndex].childIndexes.index(of: index)
                let childIndexString = childIndex.map(String.init) ?? "UNKNOWN CHILD INDEX"
                print("\(nodename(index)) -> \(nodename(parentIndex)) [label=\"child \(childIndexString)\"]")
            }
        }
        
        print("}")
    }
    
    func graphvizDumpAndOpen() {
        var output = ""
        graphvizDump(printer: { output += $0; output += "\n" })
        
        let objDescription = "\(type(of: self)) \(String(format: "%p", UInt(bitPattern: ObjectIdentifier(self))))"
        
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

extension Relation {
    public func dumpQueryPlanAndOpen() {
        QueryPlanner(roots: [(self, DirectDispatchContext().wrap({ _ in }))]).graphvizDumpAndOpen()
    }
}
