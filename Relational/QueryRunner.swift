
class QueryRunner {
    let nodeTree: ObjectSet<QueryPlanner.Node>
    let root: QueryPlanner.Node
    
    var activeNodes: ObjectSet<QueryPlanner.Node>
    
    var done = false
    
    init(nodeTree: ObjectSet<QueryPlanner.Node>) {
        self.nodeTree = nodeTree
        self.root = nodeTree.find({ $0.parents.isEmpty })!
        
        let initiators = nodeTree.filter({
            switch $0.op {
            case .TableScan:
                return true
            default:
                return false
            }
        })
        
        activeNodes = ObjectSet(initiators)
    }
    
    func pump() -> Row? {
//        guard let node = activeNodes.any else { return nil }
        
        return nil
    }
    
//    func getInitiatorRow(initiator: QueryPlanner.Node) -> Result<Row, RelationError> {
//        switch initiator.op {
//        case .TableScan(let relation):
//        }
//    }
}

extension QueryRunner {
    class NodeState {
        let node: QueryPlanner.Node
        
        init(node: QueryPlanner.Node) {
            self.node = node
        }
    }
}
