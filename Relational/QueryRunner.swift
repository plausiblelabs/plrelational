
class QueryRunner {
    let nodeTree: ObjectSet<QueryPlanner.Node>
    let root: QueryPlanner.Node
    
    var activeInitiators: ObjectSet<QueryPlanner.Node>
    
    var initiatorGenerators: ObjectDictionary<QueryPlanner.Node, AnyGenerator<Result<Row, RelationError>>> = [:]
    
    var nodeStates: ObjectDictionary<QueryPlanner.Node, NodeState> = [:]
    
    var collectedOutput: Set<Row> = []
    
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
        
        activeInitiators = ObjectSet(initiators)
    }
    
    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        var buffer: [Result<Row, RelationError>] = []
        return AnyGenerator(body: {
            while !self.done {
                if let row = buffer.popLast() {
                    return row
                } else {
                    buffer = self.pump()
                }
            }
            return nil
        })
    }
    
    private func pump() -> [Result<Row, RelationError>] {
        guard let node = activeInitiators.any else {
            done = true
            return []
        }
        
        let row = getInitiatorRow(node)
        
        switch row {
        case .None:
            activeInitiators.remove(node)
            return []
        case .Some(.Err(let err)):
            return [.Err(err)]
        case .Some(.Ok(let row)):
            writeOutput([row], fromNode: node)
            let output = collectedOutput
            collectedOutput = []
            return output.map({ .Ok($0) })
        }
    }
    
    private func getInitiatorRow(initiator: QueryPlanner.Node) -> Result<Row, RelationError>? {
        switch initiator.op {
        case .TableScan(let relation):
            let generator = initiatorGenerators.getOrCreate(initiator, defaultValue: relation.rows())
            let row = generator.next()
            return row
        default:
            fatalError("Unknown initiator operation \(initiator.op)")
        }
    }
    
    private func writeOutput(rows: Set<Row>, fromNode: QueryPlanner.Node) {
        if fromNode === root {
            collectedOutput.unionInPlace(rows)
        } else {
            for (parent, index) in fromNode.parents {
                let state = nodeStates.getOrCreate(parent, defaultValue: NodeState(node: parent))
                state.inputBuffers[index].add(rows)
                process(parent, inputIndex: index)
            }
        }
    }
    
    private func process(node: QueryPlanner.Node, inputIndex: Int) {
        let state = nodeStates[node]!
        switch node.op {
        case .Union:
            let rows = state.inputBuffers[inputIndex].popAll()
            let unique = rows.subtract(state.outputForUniquing)
            state.outputForUniquing.unionInPlace(unique)
            writeOutput(unique, fromNode: node)
        default:
            fatalError("Don't know how to process operation \(node.op)")
        }
    }
}

extension QueryRunner {
    class NodeState {
        let node: QueryPlanner.Node
        
        var outputForUniquing: Set<Row> = []
        var inputBuffers: [Buffer] = []
        
        init(node: QueryPlanner.Node) {
            self.node = node
            while inputBuffers.count < node.childCount {
                inputBuffers.append(Buffer())
            }
        }
    }
}

extension QueryRunner {
    class Buffer {
        var rows: Set<Row> = []
        
        func pop() -> Row? {
            return rows.popFirst()
        }
        
        func popAll() -> Set<Row> {
            let ret = rows
            rows = []
            return ret
        }
        
        func add<S: SequenceType where S.Generator.Element == Row>(seq: S) {
            rows.unionInPlace(seq)
        }
    }
}
