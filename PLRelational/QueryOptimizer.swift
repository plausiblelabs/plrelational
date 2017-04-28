//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

class QueryOptimizer {
    var nodes: [QueryPlanner.Node]
    
    private struct NodeOptimizationState {
        var didFilterEquijoin = false
    }
    
    private var optimizationStates: [NodeOptimizationState]
    
    init(nodes: [QueryPlanner.Node]) {
        self.nodes = nodes
        optimizationStates = Array(repeating: .init(), count: nodes.count)
        
        optimize()
    }
    
    fileprivate func optimize() {
        for i in nodes.indices {
            // Don't touch nodes with output callbacks, or we'll screw up outputs.
            if nodes[i].outputCallbacks != nil { continue }
            
            switch nodes[i].op {
                
            case .union where nodes[i].childCount == 1:
                // Unions with a single child (generated by Relation changes) can be eliminated and
                // the child pointed straight at the union's parents.
                let childIndex = nodes[i].childIndexes[0]
                nodes[childIndex].parentIndexes = nodes[i].parentIndexes
                for parentIndex in nodes[i].parentIndexes {
                    nodes[parentIndex].childIndexes.replace(i, with: childIndex)
                }
                nodes[i].parentIndexes = []
                nodes[i].childIndexes = []
                
            case .union where shouldOptimizeNestedUnions(i):
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
                nodes[i].childIndexes = []
                
            default:
                break
            }
        }
        
        nodes.indices.forEach(garbageCollect)
        QueryPlanner.validate(nodes: nodes)
    }
    
    fileprivate func shouldOptimizeNestedUnions(_ index: Int) -> Bool {
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
    
    fileprivate func isUnion(_ index: Int) -> Bool {
        if case .union = nodes[index].op {
            return true
        } else {
            return false
        }
    }
    
    /// Remove (really, detach and mark dead) any nodes which have no
    /// output callbacks and no parents. Removal is done recursively.
    fileprivate func garbageCollect(_ i: Int) {
        // Avoid redundantly examining already dead nodes.
        if case .dead = nodes[i].op {
            return
        }
        
        if nodes[i].outputCallbacks == nil && nodes[i].parentCount == 0 {
            nodes[i].op = .dead
            for childIndex in nodes[i].childIndexes {
                nodes[childIndex].parentIndexes.remove(i)
                garbageCollect(childIndex)
            }
            nodes[i].childIndexes = []
        }
    }
}
