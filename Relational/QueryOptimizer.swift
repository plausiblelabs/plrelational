//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

class QueryOptimizer {
    var nodes: [QueryPlanner.Node]
    
    init(nodes: [QueryPlanner.Node]) {
        self.nodes = nodes
        
        optimize()
    }
    
    private func optimize() {
        for i in nodes.indices {
            // Don't touch nodes with output callbacks, or we'll screw up outputs.
            if nodes[i].outputCallbacks != nil { continue }
            
            switch nodes[i].op {
                
            case .Union where nodes[i].childCount == 1:
                // Unions with a single child (generated by Relation changes) can be eliminated and
                // the child pointed straight at the union's parents.
                let childIndex = nodes[i].childIndexes[0]
                nodes[childIndex].parentIndexes = nodes[i].parentIndexes
                for parentIndex in nodes[i].parentIndexes {
                    nodes[parentIndex].childIndexes.replace(i, with: childIndex)
                }
                nodes[i].parentIndexes = []
                
            case .Union where shouldOptimizeNestedUnions(i):
                // Unions whose parents are unions can fold their operands into their parents, reducing
                // the number of layers and the amount of uniquing the query runner has to do.
                for childIndex in nodes[i].childIndexes {
                    nodes[childIndex].parentIndexes.remove(i)
                }
                for parentIndex in nodes[i].parentIndexes {
                    nodes[parentIndex].childIndexes.remove(i)
                    for childIndex in nodes[i].childIndexes {
                        nodes[parentIndex].childIndexes.append(childIndex)
                        nodes[childIndex].parentIndexes.append(parentIndex)
                    }
                }
                nodes[i].parentIndexes = []
            default:
                break
            }
        }
    }
    
    private func shouldOptimizeNestedUnions(index: Int) -> Bool {
        // We must have at least one child and one parent to perform this optimization. To prevent the optimization from taking too long,
        // limit it to cases where there are at most 10 children and 10 parents. We can only do this optimization when all parents
        // are unions. All parents must also have at most 10 children.
        return
            (1...10).contains(nodes[index].childCount) &&
            (1...10).contains(nodes[index].parentCount) &&
            nodes[index].parentIndexes.all({
                isUnion($0) && (1...10).contains(nodes[$0].childCount)
            })
    }
    
    private func isUnion(index: Int) -> Bool {
        if case .Union = nodes[index].op {
            return true
        } else {
            return false
        }
    }
}
