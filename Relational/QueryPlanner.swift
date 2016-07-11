//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

class QueryPlanner {
    typealias OutputCallback = Result<Set<Row>, RelationError> -> Void
    
    private let rootRelations: [(Relation, OutputCallback)]
    private var relationNodeIndexMap = ObjectMap<Int>()
    
    var nodes: [Node] = []
    var transactionalDatabases = ObjectDictionary<TransactionalDatabase, Int>()
    
    init(roots: [(Relation, OutputCallback)]) {
        self.rootRelations = roots
        computeNodes()
        
        let optimizer = QueryOptimizer(nodes: nodes)
        nodes = optimizer.nodes
    }
    
    var initiatorIndexes: [Int] {
        return (nodes.indices).filter({
            switch nodes[$0].op {
            case .SQLiteTableScan, .ConcreteRows, .MemoryTableScan:
                return true
            default:
                return false
            }
        })
    }
    
    var allOutputCallbacks: [OutputCallback] {
        return rootRelations.map({ $1 })
    }
    
    func initiatorRelation(initiator: QueryPlanner.Node) -> Relation {
        switch initiator.op {
        case .SQLiteTableScan(let relation):
            return relation
        default:
            fatalError("Node operation \(initiator.op) is not a known initiator operation")
        }
    }
    
    private func computeNodes() {
        visitRelationTree(rootRelations, { relation, underlyingRelation, outputCallback in
            noteTransactionalDatabases(relation, nodeIndex: 0)
            let children = relationChildren(underlyingRelation)
            let parentNodeIndex = getOrCreateNodeIndex(underlyingRelation)
            
            if let outputCallback = outputCallback {
                if nodes[parentNodeIndex].outputCallbacks == nil {
                    nodes[parentNodeIndex].outputCallbacks = [outputCallback]
                } else {
                    nodes[parentNodeIndex].outputCallbacks?.append(outputCallback)
                }
            }
            for childRelation in children {
                let childNodeIndex = getOrCreateNodeIndex(childRelation.underlyingRelationForQueryExecution)
                nodes[childNodeIndex].parentIndexes.append(parentNodeIndex)
                nodes[parentNodeIndex].childIndexes.append(childNodeIndex)
            }
        })
    }
    
    private func visitRelationTree(roots: [(Relation, OutputCallback)], @noescape _ f: (relation: Relation, underlyingRelation: Relation, outputCallback: OutputCallback?) -> Void) {
        let visited = ObjectMap<Int>()
        var rootsToVisit = roots
        var othersToVisit: [Relation] = []
        var iterationCount = 0
        while true {
            let relation: Relation
            let outputCallback: OutputCallback?
            if let (r, callback) = rootsToVisit.popLast() {
                relation = r
                outputCallback = callback
            } else if let r = othersToVisit.popLast() {
                relation = r
                outputCallback = nil
            } else {
                break
            }
            
            let realR = relation.underlyingRelationForQueryExecution
            iterationCount += 1
            if let obj = realR as? AnyObject {
                let retrievedCount = visited.getOrCreate(obj, defaultValue: iterationCount)
                if retrievedCount != iterationCount {
                    continue
                }
            }
            f(relation: relation, underlyingRelation: realR, outputCallback: outputCallback)
            othersToVisit.appendContentsOf(relationChildren(realR))
        }
    }
    
    private func getOrCreateNodeIndex(r: Relation) -> Int {
        if let obj = r as? AnyObject {
            return relationNodeIndexMap.getOrCreate(obj, defaultValue: relationToNodeIndex(r))
        } else {
            return relationToNodeIndex(r)
        }
    }
    
    private func relationToNodeIndex(r: Relation) -> Int {
        let node = relationToNode(r)
        let index = nodes.count
        nodes.append(node)
        return index
    }
    
    private func relationToNode(r: Relation) -> Node {
        switch r {
        case let r as IntermediateRelation:
            return intermediateRelationToNode(r)
        case let r as ConcreteRelation:
            return Node(op: .ConcreteRows(r.values))
        case let r as SQLiteRelation:
            return Node(op: .SQLiteTableScan(r))
        case let r as MemoryTableRelation:
            return Node(op: .MemoryTableScan(r))
        default:
            fatalError("Don't know how to handle node type \(r.dynamicType)")
        }
    }
    
    private func relationChildren(r: Relation) -> [Relation] {
        switch r {
        case let r as IntermediateRelation:
            return r.operands
        default:
            return []
        }
    }
    
    private func intermediateRelationToNode(r: IntermediateRelation) -> Node {
        switch r.op {
        case .Union:
            return Node(op: .Union)
        case .Intersection:
            return Node(op: .Intersection)
        case .Difference:
            return Node(op: .Difference)
        case .Project(let scheme):
            return Node(op: .Project(scheme))
        case .Select(let expression):
            return Node(op: .Select(expression))
        case .MutableSelect(let expression):
            return Node(op: .Select(expression))
        case .Equijoin(let matching):
            return Node(op: .Equijoin(matching))
        case .Rename(let renames):
            return Node(op: .Rename(renames))
        case .Update(let newValues):
            return Node(op: .Update(newValues))
        case .Aggregate(let attribute, let initialValue, let aggregateFunction):
            return Node(op: .Aggregate(attribute, initialValue, aggregateFunction))
        case .Otherwise:
            return Node(op: .Otherwise)
        case .Unique(let attribute, let value):
            return Node(op: .Unique(attribute, value))
        }
    }
    
    private func noteTransactionalDatabases(r: Relation, nodeIndex: Int) {
        if let
            transactionalRelation = r as? TransactionalDatabase.TransactionalRelation,
            db = transactionalRelation.db {
            transactionalDatabases[db] = nodeIndex
        }
    }
}

extension QueryPlanner {
    struct Node {
        var op: Operation
        var outputCallbacks: [OutputCallback]?
        
        var childCount: Int {
            return childIndexes.count
        }
        
        var parentCount: Int {
            return parentIndexes.count
        }
        
        var parentIndexes: [Int] = []
        
        /// All children of this node. The child is represented as its index, and the parent's
        /// index within the parent. `parentIndexInChild` is the index of the parent within the
        /// child's parentIndexes.
        var childIndexes: [Int] = []
        
        init(op: Operation) {
            self.op = op
        }
    }
    
    enum Operation {
        case SQLiteTableScan(SQLiteRelation)
        case ConcreteRows(Set<Row>)
        case MemoryTableScan(MemoryTableRelation)
        
        case Union
        case Intersection
        case Difference
        case Project(Scheme)
        case Select(SelectExpression)
        case Equijoin([Attribute: Attribute])
        case Rename([Attribute: Attribute])
        case Update(Row)
        case Aggregate(Attribute, RelationValue?, (RelationValue?, RelationValue) -> Result<RelationValue, RelationError>)
        
        case Otherwise
        case Unique(Attribute, RelationValue)
    }
}
