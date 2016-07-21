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
            case .RowGenerator, .RowSet:
                return true
            default:
                return false
            }
        })
    }
    
    var allOutputCallbacks: [OutputCallback] {
        return rootRelations.map({ $1 })
    }
    
    private func computeNodes() {
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
        switch r.contentProvider {
        case .Generator(let generatorGetter):
            return Node(op: .RowGenerator(generatorGetter))
        case .Set(let setGetter):
            return Node(op: .RowSet(setGetter))
        case .Intermediate(let op, let operands):
            return intermediateRelationToNode(op, operands)
        case .Underlying:
            fatalError("Underlying should never show up in QueryPlanner")
        }
    }
    
    private func intermediateRelationToNode(op: IntermediateRelation.Operator, _ operands: [Relation]) -> Node {
        switch op {
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
    
    private static func underlyingRelation(r: Relation) -> Relation {
        switch r.contentProvider {
        case .Underlying(let underlying):
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
        case RowGenerator(Void -> AnyGenerator<Result<Row, RelationError>>)
        case RowSet(Void -> Set<Row>)
        
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

/// Tree walking utilities.
extension QueryPlanner {
    static func visitRelationTree<AuxiliaryData>(roots: [(Relation, AuxiliaryData)], @noescape _ f: (relation: Relation, underlyingRelation: Relation, auxiliaryData: AuxiliaryData?) -> Void) {
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
            f(relation: relation, underlyingRelation: realR, auxiliaryData: auxiliaryData)
            othersToVisit.appendContentsOf(relationChildren(realR))
        }
    }
    
    private static func relationChildren(r: Relation) -> [Relation] {
        switch r {
        case let r as IntermediateRelation:
            return r.operands
        default:
            return []
        }
    }
}
