//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

#if os(OSX)
    import AppKit
    private func open(_ filename: String) {
        NSWorkspace.shared().openFile(filename, withApplication: "Graphviz")
    }
#elseif os(iOS)
    import UIKit
    private func open(_ filename: String) {
        print("WROTE \(filename)")
    }
#endif


private let colors = [
    "firebrick",
    "darkorange",
    "black",
    "bisque4",
    "blue",
    "blueviolet",
    "goldenrod",
    "green4",
    "yellow3",
]

private func randomColor() -> String {
    return colors[Int(arc4random_uniform(UInt32(colors.count)))]
}

private func graphvizDump(nodes: [QueryPlanner.Node], showChildPointers: Bool = false, includeNode: (Int) -> Bool = { _ in true }, auxNodeInfo: (Int) -> String? = { _ in nil }, printer print: (String) -> Void = { print($0) }) {
    print("digraph query_planner_graph {")
    
    func nodename(_ index: Int) -> String {
        return "node_\(index)"
    }
    
    for (index, node) in nodes.enumerated() {
        guard includeNode(index) else { continue }
        
        var opLines = String(describing: node.op).components(separatedBy: "\n")
        if opLines.count > 10 {
            opLines = opLines.prefix(10) + ["..."]
        }
        let opString = opLines.joined(separator: "\n")
        let label = [nodename(index), node.debugName.map({ "NAME: \($0)" }), node.approximateCount(true).map({ "~\($0) rows" }), String(describing: node.scheme.attributes), opString].flatMap({ $0 }).joined(separator: " ")
        let aux = auxNodeInfo(index).map({ "\n\($0)" }) ?? ""
        print("\(nodename(index)) [label=\"\(label)\(aux)\"]")
        for parentIndex in node.parentIndexes {
            guard includeNode(parentIndex) else { continue }
            
            let childIndex = nodes[parentIndex].childIndexes.index(of: index)
            let childIndexString = childIndex.map(String.init) ?? "UNKNOWN CHILD INDEX"
            print("\(nodename(index)) -> \(nodename(parentIndex)) [label=\"child \(childIndexString)\" color=\(randomColor())]")
        }
        if showChildPointers {
            for childIndex in node.childIndexes {
                guard includeNode(childIndex) else { continue }
                
                print("\(nodename(index)) -> \(nodename(childIndex)) [style=dotted arrowhead=none constraint=false]")
            }
        }
    }
    
    print("}")
}

private func internalGraphvizDumpAndOpen(object: AnyObject, nodes: [QueryPlanner.Node], showChildPointers: Bool = false, includeNode: (Int) -> Bool = { _ in true }, auxNodeInfo: (Int) -> String? = { _ in nil }) {
    var output = ""
    graphvizDump(nodes: nodes, showChildPointers: showChildPointers, includeNode: includeNode, auxNodeInfo: auxNodeInfo, printer: { output += $0; output += "\n" })
    
    let objDescription = "\(type(of: object)) \(String(format: "%p", UInt(bitPattern: ObjectIdentifier(object))))"
    
    var filename = "/tmp/\(objDescription).dot"
    var counter = 2
    while FileManager.default.fileExists(atPath: filename) {
        filename = "/tmp/\(objDescription) \(counter).dot"
        counter += 1
    }
    try! output.write(toFile: filename, atomically: true, encoding: String.Encoding.utf8)
    open(filename)
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
    func graphvizDumpAndOpen(splitOutputs: Bool = false) {
        func dump(_ includeNode: (Int) -> Bool) {
            internalGraphvizDumpAndOpen(object: self, nodes: self.nodes, includeNode: includeNode, auxNodeInfo: { index in
                let callbacksString = nodes[index].outputCallbacks.map({ "\($0.count) output callbacks\n" })
                let selectString: String? = nodeStates[index].parentalSelects.map({
                    let selectString = wordWrap("\($0)", width: 40)
                    return "Parental select: \(selectString) - \(nodeStates[index].parentalSelectsRemaining) remaining\n"
                })
                let allRowsAdded = nodeStates[index].inputBuffers.reduce(0, { $0 &+ $1.rowsAdded })
                let buffersString = "Active buffers: \(nodeStates[index].activeBuffers) - Rows input: \(allRowsAdded)"
                return (callbacksString ?? "") + (selectString ?? "") + buffersString
            })
        }
        
        if splitOutputs {
            for (index, node) in self.nodes.enumerated() {
                guard node.outputCallbacks != nil else { continue }
                print("Dumping node \(index)")
                
                var allChildren: Set<Int> = []
                func addChildren(_ index: Int) {
                    if !allChildren.contains(index) {
                        allChildren.insert(index)
                        nodes[index].childIndexes.forEach(addChildren)
                    }
                }
                addChildren(index)
                
                dump(allChildren.contains)
            }
        } else {
            dump({ _ in true })
        }
    }
}

/// :nodoc:
extension Relation {
    public func dumpQueryPlanAndOpen() {
        QueryPlanner(roots: [(self, DirectDispatchContext().wrap({ _ in }))]).graphvizDumpAndOpen()
    }
}
