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
            var opLines = String(node.op).componentsSeparatedByString("\n")
            if opLines.count > 10 {
                opLines = opLines.prefix(10) + ["..."]
            }
            let opString = opLines.joinWithSeparator("\n")
            let label = "\(nodename(index)) \(opString)"
            print("\(nodename(index)) [label=\"\(label)\"]")
            for parentIndex in node.parentIndexes {
                let childIndex = nodes[parentIndex].childIndexes.indexOf(index)
                let childIndexString = childIndex.map(String.init) ?? "UNKNOWN CHILD INDEX"
                print("\(nodename(index)) -> \(nodename(parentIndex)) [label=\"child \(childIndexString)\"]")
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
