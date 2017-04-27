//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

class QueryPlanner {
    typealias OutputCallback = DispatchContextWrapped<(Result<Set<Row>, RelationError>) -> Void>
    
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
        return nodes.indices.filter({
            QueryPlanner.isInitiator(op: nodes[$0].op)
        })
    }
    
    var allOutputCallbacks: [OutputCallback] {
        return rootRelations.map({ $1 })
    }
    
    fileprivate func computeNodes() {
        QueryPlanner.visitRelationTree(rootRelations, { relation, underlyingRelation, outputCallback in
            noteTransactionalDatabases(relation, nodeIndex: 0)
            let parentNodeIndex = getOrCreateNodeIndex(underlyingRelation)
            let children = QueryPlanner.isInitiator(op: nodes[parentNodeIndex].op)
                ? []
                : QueryPlanner.relationChildren(underlyingRelation)
            
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
        var node = relationToNode(r)
        node.debugName = r.debugName
        let index = nodes.count
        nodes.append(node)
        return index
    }
    
    fileprivate func relationToNode(_ r: Relation) -> Node {
        switch r.contentProvider {
        case .generator(let generatorGetter, let approximateCount):
            return Node(op: .rowGenerator(generatorGetter), scheme: r.scheme, approximateCount: { _ in approximateCount })
        case .efficientlySelectableGenerator(let generatorGetter, let approximateCount):
            return Node(op: .selectableGenerator(generatorGetter), scheme: r.scheme, approximateCount: approximateCount)
        case .set(let setGetter, let approximateCount):
            return Node(op: .rowSet(setGetter), scheme: r.scheme, approximateCount: { _ in approximateCount })
        case .intermediate(let op, let operands):
            return intermediateRelationToNode(r, op, operands)
        case .underlying:
            fatalError("Underlying should never show up in QueryPlanner")
        }
    }
    
    fileprivate func intermediateRelationToNode(_ r: Relation, _ op: IntermediateRelation.Operator, _ operands: [Relation]) -> Node {
        switch op {
        case .union:
            return Node(op: .union, scheme: r.scheme)
        case .intersection:
            return Node(op: .intersection, scheme: r.scheme)
        case .difference:
            return Node(op: .difference, scheme: r.scheme)
        case .project(let scheme):
            return Node(op: .project(scheme), scheme: r.scheme)
        case .select(let expression):
            return Node(op: .select(expression), scheme: r.scheme)
        case .mutableSelect(let expression):
            return Node(op: .select(expression), scheme: r.scheme)
        case .equijoin(let matching):
            return Node(op: .equijoin(matching), scheme: r.scheme)
        case .rename(let renames):
            return Node(op: .rename(renames), scheme: r.scheme)
        case .update(let newValues):
            return Node(op: .update(newValues), scheme: r.scheme)
        case .aggregate(let attribute, let initialValue, let aggregateFunction):
            return Node(op: .aggregate(attribute, initialValue, aggregateFunction), scheme: r.scheme)
        case .otherwise:
            return Node(op: .otherwise, scheme: r.scheme)
        case .unique(let attribute, let value):
            return Node(op: .unique(attribute, value), scheme: r.scheme)
        }
    }
    
    fileprivate func noteTransactionalDatabases(_ r: Relation, nodeIndex: Int) {
        if let
            transactionalRelation = r as? TransactionalRelation,
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
        var debugName: String?
        var op: Operation
        var scheme: Scheme
        var outputCallbacks: [OutputCallback]?
        var approximateCount: (SelectExpression) -> Double?
        
        var parentIndexes: [Int] = []
        
        /// All children of this node.
        var childIndexes: [Int] = []
        
        var childCount: Int {
            return childIndexes.count
        }
        
        var parentCount: Int {
            return parentIndexes.count
        }
        
        init(op: Operation, scheme: Scheme, approximateCount: @escaping (SelectExpression) -> Double? = { _ in nil }) {
            self.op = op
            self.scheme = scheme
            self.approximateCount = approximateCount
        }
    }
    
    enum Operation {
        case rowGenerator((Void) -> AnyIterator<Result<Set<Row>, RelationError>>)
        case selectableGenerator((SelectExpression) -> AnyIterator<Result<Set<Row>, RelationError>>)
        case rowSet((Void) -> Set<Row>)
        
        case union
        case intersection
        case difference
        case project(Scheme)
        case select(SelectExpression)
        case equijoin([Attribute: Attribute])
        case rename([Attribute: Attribute])
        case update(Row)
        case aggregate(Attribute, RelationValue?, (RelationValue?, [Row]) -> Result<RelationValue, RelationError>)
        
        case otherwise
        case unique(Attribute, RelationValue)
        
        /// A dummy operation used for nodes which have been removed
        /// after initial planning. Removing nodes from the array
        /// would cause indexes to shift, and would also cause some
        /// inefficient copying, so instead we just mark them as dead.
        case dead
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
            let canSkip: Bool
            if let (r, callback) = rootsToVisit.popLast() {
                relation = r
                auxiliaryData = callback
                canSkip = false
            } else if let r = othersToVisit.popLast() {
                relation = r
                auxiliaryData = nil
                canSkip = true
            } else {
                break
            }
            
            let realR = underlyingRelation(relation)
            iterationCount += 1
            if let obj = asObject(realR) {
                let retrievedCount = visited.getOrCreate(obj, defaultValue: iterationCount)
                if canSkip && retrievedCount != iterationCount {
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
    
    fileprivate static func isInitiator(op: Operation) -> Bool {
        switch op {
        case .rowGenerator, .selectableGenerator, .rowSet:
            return true
        default:
            return false
        }
    }
}
