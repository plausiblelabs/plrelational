//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import AppKit


private func graphvizDump(nodes: [QueryPlanner.Node], showChildPointers: Bool = false, auxNodeInfo: (Int) -> String? = { _ in nil }, printer print: (String) -> Void = { print($0) }) {
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
        let label = [nodename(index), node.debugName.map({ "NAME: \($0)" }), node.approximateCount.map({ "~\($0) rows" }), opString].flatMap({ $0 }).joined(separator: " ")
        let aux = auxNodeInfo(index).map({ "\n\($0)" }) ?? ""
        print("\(nodename(index)) [label=\"\(label)\(aux)\"]")
        for parentIndex in node.parentIndexes {
            let childIndex = nodes[parentIndex].childIndexes.index(of: index)
            let childIndexString = childIndex.map(String.init) ?? "UNKNOWN CHILD INDEX"
            print("\(nodename(index)) -> \(nodename(parentIndex)) [label=\"child \(childIndexString)\"]")
        }
        if showChildPointers {
            for childIndex in node.childIndexes {
                print("\(nodename(index)) -> \(nodename(childIndex)) [style=dotted arrowhead=none constraint=false]")
            }
        }
    }
    
    print("}")
}

private func internalGraphvizDumpAndOpen(object: AnyObject, nodes: [QueryPlanner.Node], showChildPointers: Bool = false, auxNodeInfo: (Int) -> String? = { _ in nil }) {
    var output = ""
    graphvizDump(nodes: nodes, showChildPointers: showChildPointers, auxNodeInfo: auxNodeInfo, printer: { output += $0; output += "\n" })
    
    let objDescription = "\(type(of: object)) \(String(format: "%p", UInt(bitPattern: ObjectIdentifier(object))))"
    
    var filename = "/tmp/\(objDescription).dot"
    var counter = 2
    if FileManager.default.fileExists(atPath: filename) {
        filename = "/tmp/\(objDescription) \(counter).dot"
        counter += 1
    }
    try! output.write(toFile: filename, atomically: true, encoding: String.Encoding.utf8)
    NSWorkspace.shared().openFile(filename, withApplication: "Graphviz")
}

private func wordWrap(_ string: String, width: Int) -> String {
    var remaining = string
    var result = ""
    while !remaining.isEmpty {
        let wrapIndex = remaining.index(remaining.startIndex, offsetBy: width, limitedBy: remaining.endIndex)
        if let wrapIndex = wrapIndex {
            let whitespaceRange = remaining.rangeOfCharacter(from: .whitespaces, options: .backwards, range: remaining.startIndex ..< wrapIndex)
            let range = whitespaceRange ?? wrapIndex ..< wrapIndex
            if !result.isEmpty {
                result += "\n"
            }
            result += remaining[remaining.startIndex ..< range.lowerBound]
            remaining.removeSubrange(remaining.startIndex ..< range.upperBound)
        } else {
            result += remaining
            remaining = ""
        }
    }
    return result
}

extension QueryPlanner {
    func graphvizDumpAndOpen() {
        internalGraphvizDumpAndOpen(object: self, nodes: self.nodes)
    }
}

extension QueryRunner {
    func graphvizDump() {
        internalGraphvizDumpAndOpen(object: self, nodes: self.nodes, auxNodeInfo: { index in
            let selectString: String? = nodeStates[index].parentalSelects.map({
                let selectString = wordWrap("\($0)", width: 40)
                return "Parental select: \(selectString) - \(nodeStates[index].parentalSelectsRemaining) remaining\n"
            })
            let buffersString = "Active buffers: \(nodeStates[index].activeBuffers)"
            return (selectString ?? "") + buffersString
        })
    }
}

extension Relation {
    public func dumpQueryPlanAndOpen() {
        QueryPlanner(roots: [(self, DirectDispatchContext().wrap({ _ in }))]).graphvizDumpAndOpen()
    }
}
