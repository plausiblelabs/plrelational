//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import AppKit


extension QueryPlanner {
    func graphvizDump(printer print: String -> Void = { print($0) }) {
        print("digraph query_planner_graph {")
        
        func nodename(index: Int) -> String {
            return "node_\(index)"
        }
        
        for (index, node) in nodes.enumerate() {
            let label = "\(nodename(index)) \(node.op)"
            print("\(nodename(index)) [label=\"\(label)\"]")
            for (parentIndex, childIndex) in node.parentIndexes {
                print("\(nodename(index)) -> \(nodename(parentIndex)) [label=\"child \(childIndex)\"]")
            }
        }
        
        print("}")
    }
    
    func graphvizDumpAndOpen() {
        var output = ""
        graphvizDump(printer: { output += $0; output += "\n" })
        
        let objDescription = "\(self.dynamicType) \(String(format: "%p", ObjectIdentifier(self).uintValue))"
        
        var filename = "/tmp/\(objDescription).dot"
        var counter = 2
        if NSFileManager.defaultManager().fileExistsAtPath(filename) {
            filename = "/tmp/\(objDescription) \(counter).dot"
            counter += 1
        }
        try! output.writeToFile(filename, atomically: true, encoding: NSUTF8StringEncoding)
        NSWorkspace.sharedWorkspace().openFile(filename, withApplication: "Graphviz")
    }
}

extension Relation {
    public func dumpQueryPlanAndOpen() {
        QueryPlanner(root: self).graphvizDumpAndOpen()
    }
}
