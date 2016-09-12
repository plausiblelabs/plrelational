//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

class QueryPlanner {
    typealias OutputCallback = (Result<Set<Row>, RelationError>) -> Void
    
    fileprivate let rootRelations: [(Relation, OutputCallback)]
    fileprivate var relationNodeIndexMap = ObjectMap<Int>()
    
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
            case .rowGenerator, .rowSet:
                return true
            default:
                return false
            }
        })
    }
    
    var allOutputCallbacks: [OutputCallback] {
        return rootRelations.map({ $1 })
    }
    
    fileprivate func computeNodes() {
        QueryPlanner.visitRelationTree(rootRelations, { relation, underlyingRelation, outputCallback in
            noteTransactionalDatabases(relation, nodeIndex: 0)
            let children = QueryPlanner.relationChildren(underlyingRelation)
            let parentNodeIndex = getOrCreateNodeIndex(underlyingRelation)
            
            if let outputCallback = outputCallback {
                if nodes[parentNodeIndex].outputCallbacks == nil {
                    nodes[parentNodeIndex].outputCallbacks = [outputCallback]
                } else {
                    nodes[parentNodeIndex].outputCallbacks?.append(outputCallback)
                }
            }
            for childRelation in children {
                let childNodeIndex = getOrCreateNodeIndex(QueryPlanner.underlyingRelation(childRelation))
                nodes[childNodeIndex].parentIndexes.append(parentNodeIndex)
                nodes[parentNodeIndex].childIndexes.append(childNodeIndex)
            }
        })
    }
    
    fileprivate func getOrCreateNodeIndex(_ r: Relation) -> Int {
        if let obj = asObject(r) {
            return relationNodeIndexMap.getOrCreate(obj, defaultValue: relationToNodeIndex(r))
        } else {
            return relationToNodeIndex(r)
        }
    }
    
    fileprivate func relationToNodeIndex(_ r: Relation) -> Int {
        let node = relationToNode(r)
        let index = nodes.count
        nodes.append(node)
        return index
    }
    
    fileprivate func relationToNode(_ r: Relation) -> Node {
        switch r.contentProvider {
        case .generator(let generatorGetter):
            return Node(op: .rowGenerator(generatorGetter))
        case .set(let setGetter):
            return Node(op: .rowSet(setGetter))
        case .intermediate(let op, let operands):
            return intermediateRelationToNode(op, operands)
        case .underlying:
            fatalError("Underlying should never show up in QueryPlanner")
        }
    }
    
    fileprivate func intermediateRelationToNode(_ op: IntermediateRelation.Operator, _ operands: [Relation]) -> Node {
        switch op {
        case .union:
            return Node(op: .union)
        case .intersection:
            return Node(op: .intersection)
        case .difference:
            return Node(op: .difference)
        case .project(let scheme):
            return Node(op: .project(scheme))
        case .select(let expression):
            return Node(op: .select(expression))
        case .mutableSelect(let expression):
            return Node(op: .select(expression))
        case .equijoin(let matching):
            return Node(op: .equijoin(matching))
        case .rename(let renames):
            return Node(op: .rename(renames))
        case .update(let newValues):
            return Node(op: .update(newValues))
        case .aggregate(let attribute, let initialValue, let aggregateFunction):
            return Node(op: .aggregate(attribute, initialValue, aggregateFunction))
        case .otherwise:
            return Node(op: .otherwise)
        case .unique(let attribute, let value):
            return Node(op: .unique(attribute, value))
        }
    }
    
    fileprivate func noteTransactionalDatabases(_ r: Relation, nodeIndex: Int) {
        if let
            transactionalRelation = r as? TransactionalDatabase.TransactionalRelation,
            let db = transactionalRelation.db {
            transactionalDatabases[db] = nodeIndex
        }
    }
    
    fileprivate static func underlyingRelation(_ r: Relation) -> Relation {
        switch r.contentProvider {
        case .underlying(let underlying):
            // We may have to peel back multiple layers, so recurse in this case.
            return underlyingRelation(underlying)
        default:
            return r
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
        case rowGenerator((Void) -> AnyIterator<Result<Row, RelationError>>)
        case rowSet((Void) -> Set<Row>)
        
        case union
        case intersection
        case difference
        case project(Scheme)
        case select(SelectExpression)
        case equijoin([Attribute: Attribute])
        case rename([Attribute: Attribute])
        case update(Row)
        case aggregate(Attribute, RelationValue?, (RelationValue?, RelationValue) -> Result<RelationValue, RelationError>)
        
        case otherwise
        case unique(Attribute, RelationValue)
    }
}

/// Tree walking utilities.
extension QueryPlanner {
    static func visitRelationTree<AuxiliaryData>(_ roots: [(Relation, AuxiliaryData)], _ f: (_ relation: Relation, _ underlyingRelation: Relation, _ auxiliaryData: AuxiliaryData?) -> Void) {
        let visited = ObjectMap<Int>()
        var rootsToVisit = roots
        var othersToVisit: [Relation] = []
        var iterationCount = 0
        while true {
            let relation: Relation
            let auxiliaryData: AuxiliaryData?
            if let (r, callback) = rootsToVisit.popLast() {
                relation = r
                auxiliaryData = callback
            } else if let r = othersToVisit.popLast() {
                relation = r
                auxiliaryData = nil
            } else {
                break
            }
            
            let realR = underlyingRelation(relation)
            iterationCount += 1
            if let obj = realR as? AnyObject {
                let retrievedCount = visited.getOrCreate(obj, defaultValue: iterationCount)
                if retrievedCount != iterationCount {
                    continue
                }
            }
            f(relation, realR, auxiliaryData)
            othersToVisit.append(contentsOf: relationChildren(realR))
        }
    }
    
    fileprivate static func relationChildren(_ r: Relation) -> [Relation] {
        switch r {
        case let r as IntermediateRelation:
            return r.operands
        default:
            return []
        }
    }
}
