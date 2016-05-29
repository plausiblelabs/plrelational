
class QueryPlanner {
    let root: Relation
    var relationNodeMap: [ObjectIdentifier: Node] = [:]
    
    init(root: Relation) {
        self.root = root
    }
    
    func makeNodeTree() -> ObjectSet<Node> {
        relationNodeMap = [:]
        return relationTreeToNodeTree(root)
    }
    
    private func relationTreeToNodeTree(r: Relation) -> ObjectSet<Node> {
        var nodes: ObjectSet<Node> = []
        visitRelationTree(r, {
            let node = getOrCreateNode($0)
            nodes.insert(node)
            for (index, childRelation) in relationChildren($0).enumerate() {
                let childNode = getOrCreateNode(childRelation)
                childNode.parents.append((node, index))
                nodes.insert(childNode)
            }
        })
        return nodes
    }
    
    private func visitRelationTree(root: Relation, @noescape _ f: Relation -> Void) {
        var visited: Set<ObjectIdentifier> = []
        var toVisit: [Relation] = [root]
        while let r = toVisit.popLast() {
            if let obj = r as? AnyObject {
                let id = ObjectIdentifier(obj)
                if visited.contains(id) {
                    return
                } else {
                    visited.insert(id)
                }
            }
            f(r)
            toVisit.appendContentsOf(relationChildren(r))
        }
    }
    
    private func getOrCreateNode(r: Relation) -> Node {
        if let obj = r as? AnyObject {
            let id = ObjectIdentifier(obj)
            if let node = relationNodeMap[id] {
                return node
            } else {
                let node = relationToNode(r)
                relationNodeMap[id] = node
                return node
            }
        }
        return relationToNode(r)
    }
    
    private func relationToNode(r: Relation) -> Node {
        switch r {
        case let r as IntermediateRelation:
            return intermediateRelationToNode(r)
        default:
            return Node(op: .TableScan(r), parents: [])
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
        case .Equijoin(let matching):
            return Node(op: .Equijoin(matching))
        case .Rename(let renames):
            return Node(op: .Rename(renames))
        case .Update(let newValues):
            return Node(op: .Update(newValues))
        case .Aggregate(let attribute, let initialValue, let aggregateFunction):
            return Node(op: .Aggregate(attribute, initialValue, aggregateFunction))
        }
    }
}

extension QueryPlanner {
    class Node {
        let op: Operation
        var parents: [(node: Node, childIndex: Int)]
        
        init(op: Operation, parents: [(node: Node, childIndex: Int)] = []) {
            self.op = op
            self.parents = parents
        }
    }
    
    enum Operation {
        case TableScan(Relation)
        
        case Union
        case Intersection
        case Difference
        case Project(Scheme)
        case Select(SelectExpression)
        case Equijoin([Attribute: Attribute])
        case Rename([Attribute: Attribute])
        case Update(Row)
        case Aggregate(Attribute, RelationValue?, (RelationValue?, RelationValue) -> Result<RelationValue, RelationError>)
    }
}